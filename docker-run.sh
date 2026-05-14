#!/usr/bin/env bash
# Local test runner for Dr Clankenstein.
# Builds the image and runs the container with secrets from .env (or env vars).
# Mounts the host's ~/.openclaw for auth profile + state persistence.

set -euo pipefail

# Load .env if present.
if [[ -f ./.env ]]; then
    set -a
    # shellcheck disable=SC1091
    source ./.env
    set +a
fi

# Required env vars.
required=(SLACK_BOT_TOKEN SLACK_APP_TOKEN OPENCLAW_GATEWAY_TOKEN)
for var in "${required[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: $var is not set. Export it or put it in .env." >&2
        exit 1
    fi
done

# Optional for the very first PoC run.
: "${GITHUB_PAT:=}"

IMAGE_TAG="dr-clankenstein:local"

docker build -t "${IMAGE_TAG}" .

docker run --rm -it \
    --name dr-clankenstein \
    -v "${HOME}/.openclaw:/home/node/.openclaw:rw" \
    -e SLACK_BOT_TOKEN \
    -e SLACK_APP_TOKEN \
    -e OPENCLAW_GATEWAY_TOKEN \
    -e GITHUB_PAT \
    "${IMAGE_TAG}"
