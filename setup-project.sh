#!/usr/bin/env bash
# One-time per-project setup. Does not run Codex auth and does not launch the agent.

set -euo pipefail

D1=${D1:-/home/prebenmn/D1}
REPO=$(pwd -P)
ENV_FILE=$REPO/.env

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing $ENV_FILE. Copy .env.example to .env and fill it in." >&2
    exit 1
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
CLANKENSTEIN_CUDA_AMD64_IMAGE=${CLANKENSTEIN_CUDA_AMD64_IMAGE:-$D1/containers/agent-cuda-amd64.sif}
CLANKENSTEIN_IMAGE=${CLANKENSTEIN_IMAGE:-$CLANKENSTEIN_CUDA_AMD64_IMAGE}
OPENCLAW_CONFIG_TEMPLATE=${OPENCLAW_CONFIG_TEMPLATE:-$REPO/openclaw.json.template}
OPENCLAW_CONFIG_HOST=$CLANKENSTEIN_OPENCLAW_DIR/openclaw.json
GIT_ASKPASS_HOST=$CLANKENSTEIN_OPENCLAW_DIR/git-askpass.sh
RUNS_REPO_DIR=${RUNS_REPO_DIR:-$(basename "$RUNS_REPO_URL" .git)}

if [[ ! "$CLANKENSTEIN_GATEWAY_PORT" =~ ^[0-9]+$ ]]; then
    echo "CLANKENSTEIN_GATEWAY_PORT must be numeric." >&2
    exit 1
fi

if [[ ! -f "$OPENCLAW_CONFIG_TEMPLATE" ]]; then
    echo "Missing OpenClaw config template: $OPENCLAW_CONFIG_TEMPLATE" >&2
    exit 1
fi

for prompt_file in AGENTS.md SOUL.md USER.md HEARTBEAT.md; do
    if [[ ! -f "$REPO/$prompt_file" ]]; then
        echo "Missing prompt file: $REPO/$prompt_file" >&2
        exit 1
    fi
done

if [[ ! -f "$CLANKENSTEIN_IMAGE" ]]; then
    echo "Missing container image: $CLANKENSTEIN_IMAGE" >&2
    exit 1
fi

mkdir -p "$CLANKENSTEIN_WORKSPACE_DIR/state" "$CLANKENSTEIN_OPENCLAW_DIR/logs"
chmod 700 "$CLANKENSTEIN_OPENCLAW_DIR" 2>/dev/null || true

cat > "$GIT_ASKPASS_HOST" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    *Username*) printf '%s\n' "x-access-token" ;;
    *Password*) printf '%s\n' "${GITHUB_PAT:-}" ;;
    *) printf '\n' ;;
esac
EOF
chmod 700 "$GIT_ASKPASS_HOST"

echo "Checking GitHub access to: $RUNS_REPO_URL"
if ! GIT_ASKPASS="$GIT_ASKPASS_HOST" GIT_TERMINAL_PROMPT=0 git ls-remote "$RUNS_REPO_URL" >/dev/null; then
    echo "Cannot read the configured output repository with GITHUB_PAT." >&2
    exit 1
fi

SLACK_CHANNEL_ID_LOWER="$(printf '%s' "$SLACK_CHANNEL_ID" | tr '[:upper:]' '[:lower:]')"

if [[ -f "$OPENCLAW_CONFIG_HOST" && "${CLANKENSTEIN_RENDER_CONFIG:-0}" != "1" ]]; then
    echo "OpenClaw config already exists: $OPENCLAW_CONFIG_HOST"
    echo "Set CLANKENSTEIN_RENDER_CONFIG=1 to overwrite it."
else
    sed \
        -e "s/__OPENCLAW_GATEWAY_PORT__/$CLANKENSTEIN_GATEWAY_PORT/g" \
        -e "s/__SLACK_CHANNEL_ID__/$SLACK_CHANNEL_ID/g" \
        -e "s/__SLACK_CHANNEL_ID_LOWER__/$SLACK_CHANNEL_ID_LOWER/g" \
        -e "s/__SLACK_ALLOWED_USER_ID__/$SLACK_ALLOWED_USER_ID/g" \
        "$OPENCLAW_CONFIG_TEMPLATE" > "$OPENCLAW_CONFIG_HOST"
fi

if command -v module >/dev/null 2>&1; then
    module use /cm/shared/ex3-modules/latest/modulefiles
    module load apptainer/1.4.5
else
    echo "module command not available; assuming apptainer is already on PATH." >&2
fi

if ! command -v apptainer >/dev/null 2>&1; then
    echo "apptainer is not available on PATH." >&2
    exit 1
fi

echo "Initializing OpenClaw plugin registry in: $CLANKENSTEIN_OPENCLAW_DIR"

apptainer exec \
    --pwd /home/node \
    --env-file "$ENV_FILE" \
    --env OPENCLAW_STATE_DIR=/home/node/.openclaw \
    --env OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json \
    --bind "$CLANKENSTEIN_OPENCLAW_DIR:/home/node/.openclaw" \
    "$CLANKENSTEIN_IMAGE" \
    sh -c '
        set -eu
        export PATH="/home/node/.npm-global/bin:$PATH"
        OPENCLAW_BIN=/home/node/.npm-global/bin/openclaw
        if [ ! -x "$OPENCLAW_BIN" ]; then
            echo "Missing OpenClaw binary in image: $OPENCLAW_BIN" >&2
            exit 1
        fi
        version="$(node -p "require(\"/home/node/.npm-global/lib/node_modules/openclaw/package.json\").version")"
        echo "Image OpenClaw version: $version"

        "$OPENCLAW_BIN" plugins install "npm:@openclaw/codex@latest" --force --pin
        "$OPENCLAW_BIN" plugins install "npm:@openclaw/slack@latest" --force --pin
        "$OPENCLAW_BIN" plugins enable codex
        "$OPENCLAW_BIN" plugins enable slack
        "$OPENCLAW_BIN" plugins registry --refresh
        "$OPENCLAW_BIN" config validate
        "$OPENCLAW_BIN" plugins doctor
        "$OPENCLAW_BIN" plugins list --enabled
    '

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

cat > "$CLANKENSTEIN_WORKSPACE_DIR/state/instance.json" <<EOF
{
  "id": "$(json_escape "$CLANKENSTEIN_ID")",
  "slack_channel_id": "$(json_escape "$SLACK_CHANNEL_ID")",
  "slack_channel_name": "$(json_escape "$SLACK_CHANNEL_NAME")",
  "runs_repo_url": "$(json_escape "$RUNS_REPO_URL")",
  "runs_repo_dir": "$(json_escape "$RUNS_REPO_DIR")",
  "workspace_dir_host": "$(json_escape "$CLANKENSTEIN_WORKSPACE_DIR")",
  "workspace_dir_container": "/home/node/.openclaw/workspace",
  "openclaw_dir_host": "$(json_escape "$CLANKENSTEIN_OPENCLAW_DIR")",
  "openclaw_config_host": "$(json_escape "$OPENCLAW_CONFIG_HOST")",
  "git_askpass_host": "$(json_escape "$GIT_ASKPASS_HOST")",
  "source_repo_host": "$(json_escape "$REPO")",
  "gateway_port": $CLANKENSTEIN_GATEWAY_PORT
}
EOF

echo "Setup complete."
echo "Instance: $CLANKENSTEIN_ID"
echo "Workspace: $CLANKENSTEIN_WORKSPACE_DIR"
echo "OpenClaw state: $CLANKENSTEIN_OPENCLAW_DIR"
echo "OpenClaw config: $OPENCLAW_CONFIG_HOST"
echo "OpenClaw plugins: codex and slack initialized"
echo "Slack channel: $SLACK_CHANNEL_ID${SLACK_CHANNEL_NAME:+ ($SLACK_CHANNEL_NAME)}"
echo "Runs repo: $RUNS_REPO_URL (access verified)"
echo "Next: run the manual Codex auth command from README.MD."
