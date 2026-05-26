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

{
    id
    groups || true
    umask
    env | sort
    printf '\n--- devices ---\n'
    ls -la /dev/kfd /dev/dri /dev/dri/* 2>&1 || true
    printf '\n--- device stats ---\n'
    stat -c '%A %U %G %u:%g %n' /dev/kfd /dev/dri /dev/dri/* 2>&1 || true
    printf '\n--- access checks ---\n'
    for path in /dev/kfd /dev/dri/renderD* /dev/dri/card*; do
        [[ -e "$path" ]] || continue
        printf '%s read=%s write=%s\n' "$path" \
            "$([[ -r "$path" ]] && echo yes || echo no)" \
            "$([[ -w "$path" ]] && echo yes || echo no)"
    done
    printf '\n--- sysfs drm ---\n'
    ls -la /sys/class/drm /sys/class/drm/* 2>&1 || true
    printf '\n--- kernel modules ---\n'
    lsmod 2>/dev/null | grep -Ei 'amdgpu|amdkfd|nvidia|drm' || true
    printf '\n--- host rocm tools ---\n'
    command -v rocm-smi && rocm-smi || true
    command -v rocminfo && rocminfo || true
    command -v rocm_agent_enumerator && rocm_agent_enumerator || true
} > "$outdir/host-devices.txt" 2>&1

{
    printf 'image=%s\n' "$PROBE_IMAGE"
    ls -lh "$PROBE_IMAGE" || true
    file "$PROBE_IMAGE" || true
    printf '\n--- inspect ---\n'
    apptainer inspect "$PROBE_IMAGE" || true
    printf '\n--- inspect-json ---\n'
    apptainer inspect --json "$PROBE_IMAGE" || true
    printf '\n--- sif-list ---\n'
    apptainer sif list "$PROBE_IMAGE" || true
} > "$outdir/image.txt" 2>&1

case "$PROBE_BACKEND" in
    cuda) gpu_args=(--nv) ;;
    hip) gpu_args=(--rocm) ;;
    *) echo "Unknown PROBE_BACKEND=$PROBE_BACKEND" >&2; exit 2 ;;
esac

set +e
apptainer exec \
    "${gpu_args[@]}" \
    --pwd /tmp \
    --env PROBE_HOST_CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-}" \
    --env PROBE_HOST_GPU_DEVICE_ORDINAL="${GPU_DEVICE_ORDINAL:-}" \
    --env PROBE_HOST_HIP_VISIBLE_DEVICES="${HIP_VISIBLE_DEVICES:-}" \
    --env PROBE_HOST_ROCR_VISIBLE_DEVICES="${ROCR_VISIBLE_DEVICES:-}" \
    --bind "$REPO/multiarch:/probe:ro" \
    --bind "$outdir:/probe-output" \
    "$PROBE_IMAGE" \
    bash /probe/run-in-container.sh "$PROBE_BACKEND" \
    > "$outdir/apptainer.out" \
    2> "$outdir/apptainer.err"
apptainer_status=$?
set -e

date -u +"finished_at=%Y-%m-%dT%H:%M:%SZ" >> "$outdir/host.txt"
printf 'apptainer_exit=%s\n' "$apptainer_status" > "$outdir/exit-code.txt"
exit "$apptainer_status"
