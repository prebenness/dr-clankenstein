#!/usr/bin/env bash
set -euo pipefail

D1=${D1:-/home/prebenmn/D1}
gpus=1
cpus=1
time_limit=01:00:00
mem=""
script=""
partitions_arg=""
script_partition=""
use_script_partition=0
verbose=0
env_file=""
image_mode=${CLANKENSTEIN_IMAGE_MODE:-partition}
cuda_amd64_image=${CLANKENSTEIN_CUDA_AMD64_IMAGE:-$D1/containers/agent-cuda-amd64.sif}
cuda_arm64_image=${CLANKENSTEIN_CUDA_ARM64_IMAGE:-$D1/containers/agent-cuda-arm64.sif}
manual_image=${CLANKENSTEIN_IMAGE:-$cuda_amd64_image}
manual_gpu_mode=${CLANKENSTEIN_APPTAINER_GPU_MODE:-nv}
script_runtime="not_checked"
script_supports_partition_runtime=1

if [[ -f cluster.sbatch ]]; then
    script=cluster.sbatch
fi

if [[ -f .env ]]; then
    env_file=.env
fi

usage() {
    cat <<'EOF'
Usage: free-gpus.sh [options]

Reports where the requested Slurm job can plausibly launch now.

Options:
  --gpus N                GPUs per node. Default: from cluster.sbatch, else 1
  --cpus N                CPUs per task. Default: from cluster.sbatch, else 1
  --time HH:MM:SS         Wall time. Default: from cluster.sbatch, else 01:00:00
  --mem SIZE              Memory, e.g. 8G. Default: from cluster.sbatch if set
  --script PATH           Read resource defaults from an sbatch file
  --env-file PATH         Read image settings from an env file. Default: .env if present
  -p, --partitions LIST   Comma-separated partitions to check
  --use-script-partition  Only check the partition from --script/cluster.sbatch
  --verbose               Show image paths, pending-job details, and sbatch test output
  -h, --help              Show this help
EOF
}

die() {
    printf 'free-gpus.sh: %s\n' "$*" >&2
    exit 2
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

field() {
    local line=$1
    local key=$2

    if [[ " $line" =~ [[:space:]]${key}=([^[:space:]]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    fi
}

trim_one_line() {
    local value=$1
    value=${value//$'\r'/}
    value=${value//$'\n'/ ; }
    value=${value//$'\t'/ }
    while [[ "$value" == *"  "* ]]; do
        value=${value//  / }
    done
    value=${value# }
    value=${value% }
    printf '%s\n' "$value"
}

shorten() {
    local value=$1
    local max=$2

    if (( ${#value} > max )); then
        printf '%s...\n' "${value:0:max-3}"
    else
        printf '%s\n' "$value"
    fi
}

summarize_nodes() {
    local nodes=$1
    local node first=""
    local count=0

    [[ -n "$nodes" && "$nodes" != "-" ]] || {
        printf -- '-\n'
        return
    }

    for node in $nodes; do
        ((count += 1))
        [[ -n "$first" ]] || first=$node
    done

    if (( count <= 1 )); then
        printf '%s\n' "$first"
    else
        printf '%s+%d\n' "$first" "$((count - 1))"
    fi
}

compact_status() {
    case "$1" in
        USABLE_NOW) printf 'OK\n' ;;
        USABLE_WITH_QUEUE) printf 'QUEUE\n' ;;
        NO_RESOURCES) printf 'FULL\n' ;;
        REJECTED) printf 'REJECT\n' ;;
        BLOCKED) printf 'BLOCK\n' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

compact_why() {
    local status=$1
    local why=$2
    local pending=$3
    local pending_count=${pending%%,*}

    case "$status" in
        USABLE_NOW)
            printf -- '-\n'
            ;;
        USABLE_WITH_QUEUE)
            printf 'queue=%s\n' "$pending_count"
            ;;
        NO_RESOURCES)
            printf 'no fitting node\n'
            ;;
        REJECTED)
            printf 'scheduler rejected\n'
            ;;
        *)
            shorten "$why" 42
            ;;
    esac
}

gpu_count_from_gres() {
    local gres=$1
    local total=0
    local entry clean count

    [[ -n "$gres" && "$gres" != "(null)" ]] || {
        printf '0\n'
        return
    }

    IFS=',' read -ra entries <<<"$gres"
    for entry in "${entries[@]}"; do
        [[ "$entry" == gpu* ]] || continue
        clean=${entry%%(*}
        count=${clean##*:}
        [[ "$count" =~ ^[0-9]+$ ]] || count=1
        total=$((total + count))
    done

    printf '%d\n' "$total"
}

gpu_type_from_gres() {
    local gres=$1
    local entry clean mid

    [[ -n "$gres" && "$gres" != "(null)" ]] || {
        printf 'any\n'
        return
    }

    IFS=',' read -ra entries <<<"$gres"
    for entry in "${entries[@]}"; do
        [[ "$entry" == gpu* ]] || continue
        clean=${entry%%(*}
        IFS=':' read -ra parts <<<"$clean"
        if (( ${#parts[@]} >= 3 )); then
            mid=${parts[1]}
            [[ -n "$mid" ]] && {
                printf '%s\n' "$mid"
                return
            }
        fi
    done

    printf 'any\n'
}

gpu_count_from_tres() {
    local tres=$1
    local total=0
    local entry

    [[ -n "$tres" && "$tres" != "(null)" ]] || {
        printf '0\n'
        return
    }

    IFS=',' read -ra entries <<<"$tres"
    for entry in "${entries[@]}"; do
        if [[ "$entry" =~ ^gres/gpu(:[^=]+)?=([0-9]+)$ ]]; then
            total=$((total + BASH_REMATCH[2]))
        fi
    done

    printf '%d\n' "$total"
}

parse_mem_mb() {
    local raw=${1:-}
    local num unit

    [[ -n "$raw" ]] || {
        printf '0\n'
        return
    }

    raw=${raw^^}
    if [[ "$raw" =~ ^([0-9]+)([KMGTP]?)B?$ ]]; then
        num=${BASH_REMATCH[1]}
        unit=${BASH_REMATCH[2]}
    else
        die "cannot parse --mem value: $raw"
    fi

    case "$unit" in
        K) printf '%d\n' $(((num + 1023) / 1024)) ;;
        ""|M) printf '%d\n' "$num" ;;
        G) printf '%d\n' $((num * 1024)) ;;
        T) printf '%d\n' $((num * 1024 * 1024)) ;;
        P) printf '%d\n' $((num * 1024 * 1024 * 1024)) ;;
    esac
}

parse_gres_gpu_count() {
    local gres=$1
    local total=0
    local entry clean count

    IFS=',' read -ra entries <<<"$gres"
    for entry in "${entries[@]}"; do
        [[ "$entry" == gpu* ]] || continue
        clean=${entry%%(*}
        count=${clean##*:}
        [[ "$count" =~ ^[0-9]+$ ]] || continue
        total=$((total + count))
    done

    printf '%d\n' "$total"
}

read_sbatch_defaults() {
    local path=$1
    local line args opt value parsed_gpus

    [[ -f "$path" ]] || die "sbatch script not found: $path"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%$'\r'}
        [[ "$line" =~ ^[[:space:]]*#SBATCH[[:space:]]+(.+)$ ]] || continue
        args=${BASH_REMATCH[1]}

        read -r opt value _ <<<"$args"

        case "$opt" in
            --partition=*) script_partition=${opt#*=} ;;
            --partition|-p) [[ -n "${value:-}" ]] && script_partition=$value ;;
            --gres=*)
                parsed_gpus=$(parse_gres_gpu_count "${opt#*=}")
                (( parsed_gpus > 0 )) && gpus=$parsed_gpus
                ;;
            --gres)
                parsed_gpus=$(parse_gres_gpu_count "${value:-}")
                (( parsed_gpus > 0 )) && gpus=$parsed_gpus
                ;;
            --gpus=*) gpus=${opt#*=} ;;
            --gpus) [[ -n "${value:-}" ]] && gpus=$value ;;
            --cpus-per-task=*) cpus=${opt#*=} ;;
            --cpus-per-task|--cpus) [[ -n "${value:-}" ]] && cpus=$value ;;
            --time=*) time_limit=${opt#*=} ;;
            --time|-t) [[ -n "${value:-}" ]] && time_limit=$value ;;
            --mem=*) mem=${opt#*=} ;;
            --mem) [[ -n "${value:-}" ]] && mem=$value ;;
        esac
    done <"$path"
}

split_csv() {
    local list=$1
    local item

    IFS=',' read -ra items <<<"$list"
    for item in "${items[@]}"; do
        item=${item//[[:space:]]/}
        [[ -n "$item" ]] && printf '%s\n' "$item"
    done
}

contains_partition() {
    local parts=$1
    local want=$2
    local part

    while IFS= read -r part; do
        [[ "$part" == "$want" ]] && return 0
    done < <(split_csv "$parts")

    return 1
}

schedulable_state() {
    local state=$1
    [[ ! "$state" =~ DOWN|DRAIN|FAIL|MAINT|RESERVED|FUTURE|UNKNOWN|POWER ]]
}

format_mem() {
    local mb=$1
    if (( mb <= 0 )); then
        printf 'any'
    elif (( mb % 1048576 == 0 )); then
        printf '%dT' $((mb / 1048576))
    elif (( mb % 1024 == 0 )); then
        printf '%dG' $((mb / 1024))
    else
        printf '%dM' "$mb"
    fi
}

basename_or_dash() {
    local path=$1
    [[ -n "$path" ]] || {
        printf -- '-'
        return
    }
    basename "$path"
}

expand_runtime_path() {
    local path=$1
    path=${path//\$\{D1\}/$D1}
    path=${path//\$D1/$D1}
    path=${path/#\~/${HOME:-}}
    printf '%s\n' "$path"
}

dotenv_value() {
    local path=$1
    local key=$2
    local line value

    [[ -f "$path" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%$'\r'}
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?${key}=(.*)$ ]] || continue
        value=${BASH_REMATCH[2]}
        value=${value%%[[:space:]]#*}
        value=${value#\"}
        value=${value%\"}
        value=${value#\'}
        value=${value%\'}
        printf '%s\n' "$value"
        return 0
    done <"$path"

    return 1
}

load_runtime_config() {
    local value

    [[ -n "$env_file" ]] || return 0
    [[ -f "$env_file" ]] || die "env file not found: $env_file"

    if value=$(dotenv_value "$env_file" CLANKENSTEIN_IMAGE_MODE); then
        image_mode=$value
    fi
    if value=$(dotenv_value "$env_file" CLANKENSTEIN_CUDA_AMD64_IMAGE); then
        cuda_amd64_image=$(expand_runtime_path "$value")
    fi
    if value=$(dotenv_value "$env_file" CLANKENSTEIN_CUDA_ARM64_IMAGE); then
        cuda_arm64_image=$(expand_runtime_path "$value")
    fi
    if value=$(dotenv_value "$env_file" CLANKENSTEIN_IMAGE); then
        manual_image=$(expand_runtime_path "$value")
    fi
    if value=$(dotenv_value "$env_file" CLANKENSTEIN_APPTAINER_GPU_MODE); then
        manual_gpu_mode=$value
    fi
}

check_script_runtime_support() {
    [[ -n "$script" && -f "$script" ]] || return 0

    if [[ "$image_mode" != "partition" ]]; then
        script_runtime="$image_mode"
        return 0
    fi

    if grep -q 'select_runtime_for_partition' "$script" \
        && grep -q 'CLANKENSTEIN_CUDA_AMD64_IMAGE' "$script" \
        && grep -q 'CLANKENSTEIN_CUDA_ARM64_IMAGE' "$script"; then
        script_runtime="partition"
        script_supports_partition_runtime=1
    else
        script_runtime="stale"
        script_supports_partition_runtime=0
    fi
}

image_label() {
    local path=$1
    local name

    name=$(basename_or_dash "$path")
    if [[ -n "$path" && -f "$path" ]]; then
        printf '%s:ok\n' "$name"
    else
        printf '%s:missing\n' "$name"
    fi
}

runtime_for_partition() {
    local partition=$1

    runtime=""
    runtime_image=""
    runtime_image_label="-"
    runtime_ok=0
    runtime_reason="-"

    if [[ "$image_mode" == "manual" ]]; then
        runtime="manual/$manual_gpu_mode"
        runtime_image=$manual_image
        runtime_image_label=$(image_label "$runtime_image")
        if [[ -f "$runtime_image" ]]; then
            runtime_ok=1
            runtime_reason="manual image mode"
        else
            runtime_reason="missing manual image: $runtime_image"
        fi
        return
    fi

    if [[ "$image_mode" != "partition" ]]; then
        runtime="config"
        runtime_reason="unsupported image mode: $image_mode"
        return
    fi

    case "$partition" in
        a100q|dgx2q|hgx2q|h200q)
            runtime="cuda-amd64/nv"
            runtime_image=$cuda_amd64_image
            runtime_image_label=$(image_label "$runtime_image")
            ;;
        a40q|aarchq|huaq|gh200q)
            runtime="cuda-arm64/nv"
            runtime_image=$cuda_arm64_image
            runtime_image_label=$(image_label "$runtime_image")
            if (( ! script_supports_partition_runtime )); then
                runtime_reason="script lacks ARM image selection; copy cluster.sbatch.example to cluster.sbatch"
                return
            fi
            ;;
        milanq)
            runtime="mixed"
            runtime_reason="mixed A100/MI210 partition; use a100q or mi210q explicitly"
            return
            ;;
        mi210q|flowq|mi100q|mi50q|amdgpuq|defq)
            runtime="rocm"
            runtime_reason="ROCm launch deferred"
            return
            ;;
        *)
            runtime="unsupported"
            runtime_reason="no configured runtime for this partition"
            return
            ;;
    esac

    if [[ -f "$runtime_image" ]]; then
        runtime_ok=1
        runtime_reason="-"
    else
        runtime_reason="missing image: $runtime_image"
    fi
}

for arg in "$@"; do
    case "$arg" in
        --script=*) script=${arg#*=} ;;
        --env-file=*) env_file=${arg#*=} ;;
    esac
done

idx=1
while (( idx <= $# )); do
    arg=${!idx}
    if [[ "$arg" == "--script" ]]; then
        idx=$((idx + 1))
        (( idx <= $# )) || die "--script requires a path"
        script=${!idx}
    elif [[ "$arg" == "--env-file" ]]; then
        idx=$((idx + 1))
        (( idx <= $# )) || die "--env-file requires a path"
        env_file=${!idx}
    fi
    idx=$((idx + 1))
done

if [[ -n "$script" ]]; then
    read_sbatch_defaults "$script"
fi

load_runtime_config
check_script_runtime_support

while (($#)); do
    case "$1" in
        --gpus=*) gpus=${1#*=}; shift ;;
        --gpus) gpus=${2:-}; [[ -n "$gpus" ]] || die "--gpus requires a value"; shift 2 ;;
        --cpus=*|--cpus-per-task=*) cpus=${1#*=}; shift ;;
        --cpus|--cpus-per-task) cpus=${2:-}; [[ -n "$cpus" ]] || die "--cpus requires a value"; shift 2 ;;
        --time=*) time_limit=${1#*=}; shift ;;
        --time|-t) time_limit=${2:-}; [[ -n "$time_limit" ]] || die "--time requires a value"; shift 2 ;;
        --mem=*) mem=${1#*=}; shift ;;
        --mem) mem=${2:-}; [[ -n "$mem" ]] || die "--mem requires a value"; shift 2 ;;
        --script=*) shift ;;
        --script) shift 2 ;;
        --env-file=*) shift ;;
        --env-file) shift 2 ;;
        --partitions=*|--partition=*) partitions_arg=${1#*=}; shift ;;
        --partitions|--partition|-p) partitions_arg=${2:-}; [[ -n "$partitions_arg" ]] || die "--partitions requires a value"; shift 2 ;;
        --use-script-partition) use_script_partition=1; shift ;;
        --verbose) verbose=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ "$gpus" =~ ^[0-9]+$ && "$gpus" -gt 0 ]] || die "--gpus must be a positive integer"
[[ "$cpus" =~ ^[0-9]+$ && "$cpus" -gt 0 ]] || die "--cpus must be a positive integer"

if (( use_script_partition )); then
    [[ -n "$script_partition" ]] || die "no partition found in ${script:-sbatch script}"
    partitions_arg=$script_partition
fi

need_cmd scontrol
need_cmd squeue

declare -A node_parts node_state node_type node_total_gpu node_free_gpu node_total_cpu node_free_cpu node_total_mem node_free_mem
declare -A part_seen part_fit part_best part_best_score part_pending_count part_pending_first part_sbatch_msg part_sbatch_rc
declare -A part_free_gpu part_total_gpu part_free_cpu part_total_cpu

req_mem_mb=$(parse_mem_mb "$mem")

while IFS= read -r line; do
    node=$(field "$line" NodeName)
    [[ -n "$node" ]] || continue

    gres=$(field "$line" Gres)
    total_gpu=$(gpu_count_from_gres "$gres")
    (( total_gpu > 0 )) || continue

    parts=$(field "$line" Partitions)
    state=$(field "$line" State)
    cpu_total=$(field "$line" CPUTot)
    cpu_alloc=$(field "$line" CPUAlloc)
    mem_total=$(field "$line" RealMemory)
    mem_alloc=$(field "$line" AllocMem)
    alloc_tres=$(field "$line" AllocTRES)
    gres_used=$(field "$line" GresUsed)
    gpu_used=$(gpu_count_from_tres "$alloc_tres")
    if (( gpu_used == 0 )) && [[ -n "${gres_used:-}" ]]; then
        gpu_used=$(gpu_count_from_gres "$gres_used")
    fi

    cpu_total=${cpu_total:-0}
    cpu_alloc=${cpu_alloc:-0}
    mem_total=${mem_total:-0}
    mem_alloc=${mem_alloc:-0}
    (( gpu_used > total_gpu )) && gpu_used=$total_gpu

    node_parts[$node]=$parts
    node_state[$node]=$state
    node_type[$node]=$(gpu_type_from_gres "$gres")
    node_total_gpu[$node]=$total_gpu
    node_free_gpu[$node]=$((total_gpu - gpu_used))
    node_total_cpu[$node]=$cpu_total
    node_free_cpu[$node]=$((cpu_total - cpu_alloc))
    node_total_mem[$node]=$mem_total
    node_free_mem[$node]=$((mem_total - mem_alloc))
    (( node_free_cpu[$node] < 0 )) && node_free_cpu[$node]=0
    (( node_free_mem[$node] < 0 )) && node_free_mem[$node]=0

    while IFS= read -r part; do
        part_seen[$part]=1
    done < <(split_csv "$parts")
done < <(scontrol -o show nodes)

if [[ -n "$partitions_arg" ]]; then
    declare -A selected_parts=()
    while IFS= read -r part; do
        selected_parts[$part]=1
    done < <(split_csv "$partitions_arg")
else
    declare -A selected_parts=()
    for part in "${!part_seen[@]}"; do
        selected_parts[$part]=1
    done
fi

while IFS='|' read -r job_id part user reason; do
    [[ -n "${job_id:-}" && -n "${part:-}" ]] || continue
    while IFS= read -r one_part; do
        [[ -n "${selected_parts[$one_part]+x}" ]] || continue
        part_pending_count[$one_part]=$(( ${part_pending_count[$one_part]:-0} + 1 ))
        if [[ -z "${part_pending_first[$one_part]:-}" ]]; then
            part_pending_first[$one_part]="${job_id}/${user}/${reason}"
        fi
    done < <(split_csv "$part")
done < <(squeue -t PD -h -o "%i|%P|%u|%R" 2>/dev/null || true)

for node in "${!node_total_gpu[@]}"; do
    for part in "${!selected_parts[@]}"; do
        contains_partition "${node_parts[$node]}" "$part" || continue

        free_gpu=${node_free_gpu[$node]}
        free_cpu=${node_free_cpu[$node]}
        total_gpu=${node_total_gpu[$node]}
        total_cpu=${node_total_cpu[$node]}
        free_mem=${node_free_mem[$node]}
        total_mem=${node_total_mem[$node]}

        part_total_gpu[$part]=$(( ${part_total_gpu[$part]:-0} + total_gpu ))
        part_total_cpu[$part]=$(( ${part_total_cpu[$part]:-0} + total_cpu ))
        if schedulable_state "${node_state[$node]}"; then
            part_free_gpu[$part]=$(( ${part_free_gpu[$part]:-0} + free_gpu ))
            part_free_cpu[$part]=$(( ${part_free_cpu[$part]:-0} + free_cpu ))
        fi

        score=$((free_gpu * 1000000 + free_cpu * 1000 + free_mem / 1024))
        if [[ -z "${part_best_score[$part]+x}" || "$score" -gt "${part_best_score[$part]}" ]]; then
            part_best_score[$part]=$score
            part_best[$part]="${node}(${node_type[$node]},${free_gpu}/${total_gpu}g,${free_cpu}/${total_cpu}c"
            if (( req_mem_mb > 0 && total_mem > 0 )); then
                part_best[$part]+=",${free_mem}/${total_mem}M"
            fi
            part_best[$part]+=",${node_state[$node]})"
        fi

        if schedulable_state "${node_state[$node]}" \
            && (( free_gpu >= gpus )) \
            && (( free_cpu >= cpus )) \
            && (( req_mem_mb == 0 || total_mem == 0 || free_mem >= req_mem_mb )); then
            part_fit[$part]="${part_fit[$part]:-}${node} "
        fi
    done
done

for part in "${!selected_parts[@]}"; do
    if command -v sbatch >/dev/null 2>&1; then
        cmd=(sbatch --test-only --partition="$part" --nodes=1 --ntasks=1 --cpus-per-task="$cpus" --time="$time_limit" --gres="gpu:$gpus")
        [[ -n "$mem" ]] && cmd+=(--mem="$mem")
        cmd+=(--wrap=true)
        set +e
        msg=$("${cmd[@]}" 2>&1)
        rc=$?
        set -e
        part_sbatch_rc[$part]=$rc
        part_sbatch_msg[$part]=$(trim_one_line "$msg")
    else
        part_sbatch_rc[$part]=127
        part_sbatch_msg[$part]="sbatch not found"
    fi
done

request_mem=$(format_mem "$req_mem_mb")
printf 'REQUEST gpus=%s cpus=%s mem=%s time=%s' "$gpus" "$cpus" "$request_mem" "$time_limit"
[[ -n "$script" ]] && printf ' script=%s' "$script"
[[ -n "$script_partition" ]] && printf ' script_partition=%s' "$script_partition"
printf ' image_mode=%s' "$image_mode"
[[ -n "$script" ]] && printf ' script_runtime=%s' "$script_runtime"
printf '\n'

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

for part in "${!selected_parts[@]}"; do
    runtime_for_partition "$part"
    why=$runtime_reason

    if (( ! runtime_ok )); then
        rank=3
        status="BLOCKED"
        fit_nodes=${part_fit[$part]:-}
        fit_nodes=$(trim_one_line "$fit_nodes")
        [[ -n "$fit_nodes" ]] || fit_nodes="-"
    elif [[ -n "${part_fit[$part]:-}" ]]; then
        if (( ${part_pending_count[$part]:-0} > 0 )); then
            rank=1
            status="USABLE_WITH_QUEUE"
            why="pending jobs ahead"
        else
            rank=0
            status="USABLE_NOW"
            why="-"
        fi
        fit_nodes=$(trim_one_line "${part_fit[$part]}")
    else
        rank=2
        status="NO_RESOURCES"
        fit_nodes="-"
        why="no node currently fits request"
    fi

    if (( ${part_sbatch_rc[$part]:-0} != 0 )); then
        if [[ "$status" != "BLOCKED" ]]; then
            status="REJECTED"
            rank=3
            why=${part_sbatch_msg[$part]:-"sbatch test failed"}
        fi
    fi

    pending="${part_pending_count[$part]:-0}"
    [[ -n "${part_pending_first[$part]:-}" ]] && pending+=",first=${part_pending_first[$part]}"

    free="${part_free_gpu[$part]:-0}/${part_total_gpu[$part]:-0}g,${part_free_cpu[$part]:-0}/${part_total_cpu[$part]:-0}c"
    best=${part_best[$part]:--}
    sched=${part_sbatch_msg[$part]:--}
    if (( ${#sched} > 110 )); then
        sched="${sched:0:107}..."
    fi
    if (( ${#why} > 90 )); then
        why="${why:0:87}..."
    fi

    printf '%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$rank" "$status" "$part" "$runtime" "$runtime_image_label" "$fit_nodes" "$free" "$best" "$pending" "$why" "$sched" >>"$tmp"
done

if (( verbose )); then
    {
        printf 'STATUS\tPARTITION\tRUNTIME\tIMAGE\tFIT_NODES\tFREE\tBEST_NODE\tPENDING\tWHY\tSBATCH_TEST\n'
        sort -t$'\t' -k1,1n -k3,3 "$tmp" | cut -f2-
    } | {
        if command -v column >/dev/null 2>&1; then
            column -t -s $'\t'
        else
            cat
        fi
    }
else
    {
        printf 'STATUS\tPARTITION\tRUNTIME\tFIT\tFREE\tBEST\tNOTE\n'
        while IFS=$'\t' read -r _rank status part runtime _image fit_nodes free best pending why _sched; do
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$(compact_status "$status")" \
                "$part" \
                "$runtime" \
                "$(summarize_nodes "$fit_nodes")" \
                "$free" \
                "$(shorten "$best" 34)" \
                "$(compact_why "$status" "$why" "$pending")"
        done < <(sort -t$'\t' -k1,1n -k3,3 "$tmp")
    } | {
        if command -v column >/dev/null 2>&1; then
            column -t -s $'\t'
        else
            cat
        fi
    }
    printf '\nUse --verbose for image checks, pending-job details, and sbatch --test-only output.\n'
fi
