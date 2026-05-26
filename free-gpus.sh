#!/usr/bin/env bash
set -euo pipefail

gpus=1
cpus=1
time_limit=01:00:00
mem=""
script=""
partitions_arg=""
script_partition=""
use_script_partition=0

if [[ -f cluster.sbatch ]]; then
    script=cluster.sbatch
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
  -p, --partitions LIST   Comma-separated partitions to check
  --use-script-partition  Only check the partition from --script/cluster.sbatch
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

for arg in "$@"; do
    case "$arg" in
        --script=*) script=${arg#*=} ;;
    esac
done

idx=1
while (( idx <= $# )); do
    arg=${!idx}
    if [[ "$arg" == "--script" ]]; then
        idx=$((idx + 1))
        (( idx <= $# )) || die "--script requires a path"
        script=${!idx}
    fi
    idx=$((idx + 1))
done

if [[ -n "$script" ]]; then
    read_sbatch_defaults "$script"
fi

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
        --partitions=*|--partition=*) partitions_arg=${1#*=}; shift ;;
        --partitions|--partition|-p) partitions_arg=${2:-}; [[ -n "$partitions_arg" ]] || die "--partitions requires a value"; shift 2 ;;
        --use-script-partition) use_script_partition=1; shift ;;
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
printf '\n'

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

for part in "${!selected_parts[@]}"; do
    if [[ -n "${part_fit[$part]:-}" ]]; then
        if (( ${part_pending_count[$part]:-0} > 0 )); then
            rank=1
            status="FIT_WITH_QUEUE"
        else
            rank=0
            status="FIT_NOW"
        fi
        fit_nodes=$(trim_one_line "${part_fit[$part]}")
    else
        rank=2
        status="NO_FIT"
        fit_nodes="-"
    fi

    if (( ${part_sbatch_rc[$part]:-0} != 0 )); then
        if [[ "$status" == "NO_FIT" ]]; then
            status="REJECTED"
            rank=3
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

    printf '%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$rank" "$status" "$part" "$fit_nodes" "$free" "$best" "$pending" "$sched" >>"$tmp"
done

{
    printf 'STATUS\tPARTITION\tFIT_NODES\tFREE\tBEST_NODE\tPENDING\tSBATCH_TEST\n'
    sort -t$'\t' -k1,1n -k3,3 "$tmp" | cut -f2-
} | {
    if command -v column >/dev/null 2>&1; then
        column -t -s $'\t'
    else
        cat
    fi
}
