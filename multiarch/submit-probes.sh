#!/usr/bin/env bash
set -euo pipefail

D1=${D1:-/home/prebenmn/D1}
REPO=$(pwd -P)
MATRIX=${MATRIX:-$REPO/multiarch/probe-matrix.tsv}
IMAGE_DIR=${IMAGE_DIR:-$D1/containers/multiarch-probes}
RESULTS_DIR=${RESULTS_DIR:-$REPO/multiarch/results}
DRY_RUN=0
WAIT=0
ONLY=""

usage() {
    cat <<'EOF'
Usage: submit-probes.sh [--dry-run] [--wait] [--only name[,name...]]

Run from the dr-clankenstein repo on EX3.
EOF
}

contains_name() {
    local haystack=$1
    local needle=$2
    local item

    [[ -z "$haystack" ]] && return 0
    IFS=',' read -ra items <<<"$haystack"
    for item in "${items[@]}"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --wait) WAIT=1; shift ;;
        --only) ONLY=${2:-}; [[ -n "$ONLY" ]] || { echo "--only requires a value" >&2; exit 2; }; shift 2 ;;
        --only=*) ONLY=${1#*=}; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -f "$MATRIX" ]] || { echo "Missing matrix: $MATRIX" >&2; exit 1; }
mkdir -p "$RESULTS_DIR"
failed=0

while IFS=$'\t' read -r name partition backend image gpus cpus time_limit; do
    [[ -n "${name:-}" && "$name" != \#* ]] || continue
    contains_name "$ONLY" "$name" || continue

    sif=$IMAGE_DIR/$image.sif
    if [[ ! -f "$sif" && "$DRY_RUN" != "1" ]]; then
        echo "Missing image for $name: $sif" >&2
        exit 1
    fi

    export_arg="ALL,PROBE_NAME=$name,PROBE_BACKEND=$backend,PROBE_IMAGE=$sif,PROBE_RESULTS_BASE=$RESULTS_DIR"
    cmd=(
        sbatch
        --partition "$partition"
        --gres "gpu:$gpus"
        --cpus-per-task "$cpus"
        --time "$time_limit"
        --job-name "probe-$name"
        --output "$RESULTS_DIR/%x-%j.out"
        --error "$RESULTS_DIR/%x-%j.err"
        --export "$export_arg"
        "$REPO/multiarch/probe.sbatch"
    )
    if [[ "$WAIT" == "1" ]]; then
        cmd=(sbatch --wait "${cmd[@]:1}")
    fi

    printf '%q ' "${cmd[@]}"
    printf '\n'
    if [[ "$DRY_RUN" != "1" ]]; then
        set +e
        "${cmd[@]}"
        rc=$?
        set -e
        if (( rc != 0 )); then
            echo "probe failed: $name rc=$rc" >&2
            failed=1
        fi
    fi
done <"$MATRIX"

exit "$failed"
