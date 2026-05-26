#!/usr/bin/env bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --time=00:10:00

set -euo pipefail

REPO=${SLURM_SUBMIT_DIR:-$(pwd -P)}

: "${PROBE_NAME:?}"
: "${PROBE_BACKEND:?}"
: "${PROBE_IMAGE:?}"
: "${PROBE_RESULTS_BASE:?}"

if command -v module >/dev/null 2>&1; then
    module use /cm/shared/ex3-modules/latest/modulefiles
    module load apptainer/1.4.5
fi

outdir=$PROBE_RESULTS_BASE/$PROBE_NAME-${SLURM_JOB_ID:-manual}
mkdir -p "$outdir"

{
    date -u +"started_at=%Y-%m-%dT%H:%M:%SZ"
    printf 'probe_name=%s\n' "$PROBE_NAME"
    printf 'backend=%s\n' "$PROBE_BACKEND"
    printf 'image=%s\n' "$PROBE_IMAGE"
    printf 'job_id=%s\n' "${SLURM_JOB_ID:-}"
    printf 'partition=%s\n' "${SLURM_JOB_PARTITION:-}"
    printf 'node_list=%s\n' "${SLURM_JOB_NODELIST:-}"
    uname -a
    command -v apptainer || true
    apptainer --version || true
    if [[ -n "${SLURM_JOB_ID:-}" ]] && command -v scontrol >/dev/null 2>&1; then
        scontrol -o show job "$SLURM_JOB_ID" || true
        scontrol -o show node "${SLURM_JOB_NODELIST%%,*}" || true
    fi
} > "$outdir/host.txt" 2>&1

case "$PROBE_BACKEND" in
    cuda) gpu_args=(--nv) ;;
    hip) gpu_args=(--rocm) ;;
    *) echo "Unknown PROBE_BACKEND=$PROBE_BACKEND" >&2; exit 2 ;;
esac

apptainer exec \
    "${gpu_args[@]}" \
    --bind "$REPO/multiarch:/probe:ro" \
    --bind "$outdir:/probe-output" \
    "$PROBE_IMAGE" \
    bash /probe/run-in-container.sh "$PROBE_BACKEND"

date -u +"finished_at=%Y-%m-%dT%H:%M:%SZ" >> "$outdir/host.txt"
