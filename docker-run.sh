#!/usr/bin/env bash
# Local smoke-test runner. EX3 production runs use cluster.sbatch.
# Run setup-project.sh first.

set -euo pipefail

if [[ -f ./.env ]]; then
    set -a
    # shellcheck disable=SC1091
    source ./.env
    set +a
fi

required=(
    CLANKENSTEIN_ID
    SLACK_BOT_TOKEN
    SLACK_APP_TOKEN
    SLACK_CHANNEL_ID
    OPENCLAW_GATEWAY_TOKEN
    RUNS_REPO_URL
)

for var in "${required[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: $var is not set. Export it or put it in .env." >&2
        exit 1
    fi
done

CLANKENSTEIN_WORKSPACE_DIR=${CLANKENSTEIN_WORKSPACE_DIR:-$PWD/.local/workspace}
CLANKENSTEIN_OPENCLAW_DIR=${CLANKENSTEIN_OPENCLAW_DIR:-$PWD/.local/openclaw}
OPENCLAW_CONFIG_HOST=$CLANKENSTEIN_OPENCLAW_DIR/openclaw.json
GIT_ASKPASS_HOST=$CLANKENSTEIN_OPENCLAW_DIR/git-askpass.sh

if [[ ! -f "$OPENCLAW_CONFIG_HOST" || ! -x "$GIT_ASKPASS_HOST" ]]; then
    echo "Missing local setup state. Run: bash setup-project.sh" >&2
    exit 1
fi

: "${GITHUB_PAT:=}"

IMAGE_TAG="dr-clankenstein:local"

docker build -t "${IMAGE_TAG}" .

docker run --rm -it \
    --name "dr-clankenstein-${CLANKENSTEIN_ID}" \
    -v "${CLANKENSTEIN_OPENCLAW_DIR}:/home/node/.openclaw:rw" \
    -v "${CLANKENSTEIN_WORKSPACE_DIR}:/home/node/.openclaw/workspace:rw" \
    -v "${PWD}/AGENTS.md:/home/node/.openclaw/workspace/AGENTS.md:ro" \
    -v "${PWD}/SOUL.md:/home/node/.openclaw/workspace/SOUL.md:ro" \
    -v "${PWD}/HEARTBEAT.md:/home/node/.openclaw/workspace/HEARTBEAT.md:ro" \
    -v "${PWD}/USER.md:/home/node/.openclaw/workspace/USER.md:ro" \
    -e OPENCLAW_STATE_DIR=/home/node/.openclaw \
    -e OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json \
    -e GIT_ASKPASS=/home/node/.openclaw/git-askpass.sh \
    -e GIT_TERMINAL_PROMPT=0 \
    -e SLACK_BOT_TOKEN \
    -e SLACK_APP_TOKEN \
    -e OPENCLAW_GATEWAY_TOKEN \
    -e GITHUB_PAT \
    "${IMAGE_TAG}"
