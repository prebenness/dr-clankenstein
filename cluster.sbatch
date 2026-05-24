#!/usr/bin/env bash
#SBATCH --job-name=experiment
#SBATCH --partition=dgx2q
#SBATCH --gres=gpu:2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=24:00:00
#SBATCH --chdir=/home/prebenmn/D1/workspace/dr-clankenstein
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=prebenmn@simula.no

set -euo pipefail

mkdir -p logs

module use /cm/shared/ex3-modules/latest/modulefiles
module load apptainer/1.4.5

D1=/home/prebenmn/D1
REPO=$D1/workspace/dr-clankenstein
JOB_STATE=$D1/agent-workspace/state/slurm-job.json

mkdir -p "$(dirname "$JOB_STATE")"

JOB_INFO=""
if [[ -n "${SLURM_JOB_ID:-}" ]] && command -v scontrol >/dev/null 2>&1; then
    JOB_INFO="$(scontrol -o show job "$SLURM_JOB_ID" 2>/dev/null || true)"
fi

JOB_START_TIME="$(printf '%s\n' "$JOB_INFO" | sed -n 's/.*StartTime=\([^ ]*\).*/\1/p')"
JOB_END_TIME="$(printf '%s\n' "$JOB_INFO" | sed -n 's/.*EndTime=\([^ ]*\).*/\1/p')"
JOB_TIME_LIMIT="$(printf '%s\n' "$JOB_INFO" | sed -n 's/.*TimeLimit=\([^ ]*\).*/\1/p')"
JOB_OBSERVED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
JOB_OBSERVED_AT_EPOCH="$(date -u +%s)"
JOB_END_TIME_EPOCH=""

if [[ -z "$JOB_START_TIME" || "$JOB_START_TIME" == "Unknown" ]]; then
    JOB_START_TIME="$JOB_OBSERVED_AT"
fi

if [[ -n "$JOB_END_TIME" && "$JOB_END_TIME" != "Unknown" ]]; then
    JOB_END_TIME_EPOCH="$(date -d "$JOB_END_TIME" +%s 2>/dev/null || true)"
fi

cat > "$JOB_STATE" <<EOF
{
  "job_id": "${SLURM_JOB_ID:-}",
  "started_at": "$JOB_START_TIME",
  "ends_at": "$JOB_END_TIME",
  "ends_at_epoch": ${JOB_END_TIME_EPOCH:-null},
  "time_limit": "$JOB_TIME_LIMIT",
  "observed_at_utc": "$JOB_OBSERVED_AT",
  "observed_at_epoch": $JOB_OBSERVED_AT_EPOCH,
  "message": "JOB STARTED"
}
EOF

echo "JOB STARTED: id=${SLURM_JOB_ID:-unknown} start=$JOB_START_TIME end=${JOB_END_TIME:-unknown} limit=${JOB_TIME_LIMIT:-unknown}"

apptainer run \
    --nv \
    --pwd /home/node \
    --env LD_LIBRARY_PATH=/.singularity.d/libs \
    --bind "$HOME/.openclaw:/home/node/.openclaw" \
    --bind "$HOME/.gitconfig:/home/node/.gitconfig:ro" \
    --bind "$D1/agent-workspace:/home/node/.openclaw/workspace" \
    --bind "$REPO/AGENTS.md:/home/node/.openclaw/workspace/AGENTS.md:ro" \
    --bind "$REPO/BOOT.md:/home/node/.openclaw/workspace/BOOT.md:ro" \
    --bind "$REPO/HEARTBEAT.md:/home/node/.openclaw/workspace/HEARTBEAT.md:ro" \
    --bind "$REPO/USER.md:/home/node/.openclaw/workspace/USER.md:ro" \
    --env-file "$REPO/.env" \
    "$D1/containers/agent.sif"
