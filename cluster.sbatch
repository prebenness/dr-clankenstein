#!/usr/bin/env bash
#SBATCH --job-name=clankenstein
#SBATCH --partition=dgx2q
#SBATCH --gres=gpu:2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=24:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=prebenmn@simula.no

set -euo pipefail

D1=/home/prebenmn/D1
REPO=${SLURM_SUBMIT_DIR:-$(pwd -P)}
ENV_FILE=$REPO/.env

cd "$REPO"
mkdir -p logs

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing $ENV_FILE. Copy .env.example to .env and fill it in." >&2
    exit 1
fi

if command -v module >/dev/null 2>&1; then
    module use /cm/shared/ex3-modules/latest/modulefiles
    module load apptainer/1.4.5
else
    echo "module command not available; assuming apptainer is already on PATH." >&2
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

required=(
    CLANKENSTEIN_ID
    SLACK_BOT_TOKEN
    SLACK_APP_TOKEN
    SLACK_CHANNEL_ID
    OPENCLAW_GATEWAY_TOKEN
    RUNS_REPO_URL
    GITHUB_PAT
)

for var in "${required[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "Missing required .env variable: $var" >&2
        exit 1
    fi
done

if [[ ! "$CLANKENSTEIN_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "CLANKENSTEIN_ID may only contain letters, numbers, '.', '_', and '-'." >&2
    exit 1
fi

if [[ ! "$SLACK_CHANNEL_ID" =~ ^[A-Za-z0-9]+$ ]]; then
    echo "SLACK_CHANNEL_ID should be the Slack channel id, for example C012ABCDEF0." >&2
    exit 1
fi

SLACK_ALLOWED_USER_ID=${SLACK_ALLOWED_USER_ID:-U0B364S9A01}
SLACK_CHANNEL_NAME=${SLACK_CHANNEL_NAME:-}
CLANKENSTEIN_WORKSPACE_DIR=${CLANKENSTEIN_WORKSPACE_DIR:-$D1/agent-workspaces/$CLANKENSTEIN_ID}
CLANKENSTEIN_OPENCLAW_DIR=${CLANKENSTEIN_OPENCLAW_DIR:-$D1/openclaw-state/$CLANKENSTEIN_ID}
CLANKENSTEIN_GATEWAY_PORT=${CLANKENSTEIN_GATEWAY_PORT:-18789}
CLANKENSTEIN_IMAGE=${CLANKENSTEIN_IMAGE:-$D1/containers/agent.sif}
OPENCLAW_CONFIG_HOST=$CLANKENSTEIN_OPENCLAW_DIR/openclaw.json
GIT_ASKPASS_HOST=$CLANKENSTEIN_OPENCLAW_DIR/git-askpass.sh
RUNS_REPO_DIR=${RUNS_REPO_DIR:-$(basename "$RUNS_REPO_URL" .git)}
INSTANCE_FILE=$CLANKENSTEIN_WORKSPACE_DIR/state/instance.json

if [[ ! -d "$CLANKENSTEIN_WORKSPACE_DIR" ]]; then
    echo "Missing workspace dir: $CLANKENSTEIN_WORKSPACE_DIR" >&2
    echo "Run: bash setup-project.sh" >&2
    exit 1
fi

if [[ ! -d "$CLANKENSTEIN_OPENCLAW_DIR" ]]; then
    echo "Missing OpenClaw state dir: $CLANKENSTEIN_OPENCLAW_DIR" >&2
    echo "Run: bash setup-project.sh" >&2
    exit 1
fi

if [[ ! -f "$OPENCLAW_CONFIG_HOST" ]]; then
    echo "Missing OpenClaw config: $OPENCLAW_CONFIG_HOST" >&2
    echo "Run: bash setup-project.sh" >&2
    exit 1
fi

if [[ ! -f "$INSTANCE_FILE" ]]; then
    echo "Missing instance file: $INSTANCE_FILE" >&2
    echo "Run: bash setup-project.sh" >&2
    exit 1
fi

if [[ ! -d "$CLANKENSTEIN_WORKSPACE_DIR/state" ]]; then
    echo "Missing workspace state dir: $CLANKENSTEIN_WORKSPACE_DIR/state" >&2
    echo "Run: bash setup-project.sh" >&2
    exit 1
fi

if [[ ! -x "$GIT_ASKPASS_HOST" ]]; then
    echo "Missing executable git askpass helper: $GIT_ASKPASS_HOST" >&2
    echo "Run: bash setup-project.sh" >&2
    exit 1
fi

require_instance_value() {
    local key=$1
    local value=$2

    if ! grep -Fq "\"$key\": \"$value\"" "$INSTANCE_FILE"; then
        echo "Instance file does not match .env for $key." >&2
        echo "Run: bash setup-project.sh" >&2
        exit 1
    fi
}

require_instance_value id "$CLANKENSTEIN_ID"
require_instance_value slack_channel_id "$SLACK_CHANNEL_ID"
require_instance_value runs_repo_url "$RUNS_REPO_URL"

if ! grep -Fq "\"gateway_port\": $CLANKENSTEIN_GATEWAY_PORT" "$INSTANCE_FILE"; then
    echo "Instance file does not match .env for gateway_port." >&2
    echo "Run: bash setup-project.sh" >&2
    exit 1
fi

echo "Instance: $CLANKENSTEIN_ID"
echo "Workspace: $CLANKENSTEIN_WORKSPACE_DIR"
echo "OpenClaw state: $CLANKENSTEIN_OPENCLAW_DIR"
echo "OpenClaw config: $OPENCLAW_CONFIG_HOST"
echo "Slack channel: $SLACK_CHANNEL_ID${SLACK_CHANNEL_NAME:+ ($SLACK_CHANNEL_NAME)}"
echo "Runs repo: $RUNS_REPO_URL"

JOB_STATE=$CLANKENSTEIN_WORKSPACE_DIR/state/slurm-job.json

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
    --env-file "$ENV_FILE" \
    --env LD_LIBRARY_PATH=/.singularity.d/libs \
    --env OPENCLAW_STATE_DIR=/home/node/.openclaw \
    --env OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json \
    --env GIT_ASKPASS=/home/node/.openclaw/git-askpass.sh \
    --env GIT_TERMINAL_PROMPT=0 \
    --bind "$CLANKENSTEIN_OPENCLAW_DIR:/home/node/.openclaw" \
    --bind "$HOME/.gitconfig:/home/node/.gitconfig:ro" \
    --bind "$CLANKENSTEIN_WORKSPACE_DIR:/home/node/.openclaw/workspace" \
    --bind "$REPO/AGENTS.md:/home/node/.openclaw/workspace/AGENTS.md:ro" \
    --bind "$REPO/BOOT.md:/home/node/.openclaw/workspace/BOOT.md:ro" \
    --bind "$REPO/HEARTBEAT.md:/home/node/.openclaw/workspace/HEARTBEAT.md:ro" \
    --bind "$REPO/USER.md:/home/node/.openclaw/workspace/USER.md:ro" \
    "$CLANKENSTEIN_IMAGE"
