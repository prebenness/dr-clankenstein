#!/usr/bin/env bash
# Manual Codex auth helper. Run after setup-project.sh.

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

if command -v module >/dev/null 2>&1; then
    module use /cm/shared/ex3-modules/latest/modulefiles
    module load apptainer/1.4.5
else
    echo "module command not available; assuming apptainer is already on PATH." >&2
fi

CLANKENSTEIN_OPENCLAW_DIR=${CLANKENSTEIN_OPENCLAW_DIR:-$D1/openclaw-state/${CLANKENSTEIN_ID:?CLANKENSTEIN_ID is required}}
CLANKENSTEIN_IMAGE=${CLANKENSTEIN_IMAGE:-$D1/containers/agent.sif}
OPENCLAW_CONFIG_HOST=$CLANKENSTEIN_OPENCLAW_DIR/openclaw.json

if [[ ! -f "$OPENCLAW_CONFIG_HOST" ]]; then
    echo "Missing OpenClaw config: $OPENCLAW_CONFIG_HOST" >&2
    echo "Run: bash setup-project.sh" >&2
    exit 1
fi

mode=${1:-login}

case "$mode" in
    login)
        set -- openclaw models auth login --provider openai-codex
        ;;
    list)
        set -- openclaw models auth list --provider openai-codex
        ;;
    validate-config)
        set -- openclaw config validate
        ;;
    *)
        echo "Usage: bash auth-codex.sh [login|list|validate-config]" >&2
        exit 1
        ;;
esac

apptainer exec \
    --pwd /home/node \
    --env-file "$ENV_FILE" \
    --env OPENCLAW_STATE_DIR=/home/node/.openclaw \
    --env OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json \
    --bind "$CLANKENSTEIN_OPENCLAW_DIR:/home/node/.openclaw" \
    "$CLANKENSTEIN_IMAGE" \
    "$@"
