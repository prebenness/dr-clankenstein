# Dr Clankenstein research agent - OpenClaw container
# Single-container deployment. Container is the security boundary;
# OpenClaw's tool sandbox is disabled (no DinD).

FROM node:20-bookworm-slim

ARG OPENCLAW_VERSION=2026.5.7
ENV OPENCLAW_VERSION=${OPENCLAW_VERSION}

# System deps: git for agent repo operations, curl + ca-certs for general use,
# tini as PID 1 so SIGTERM from docker/Slurm reaches the gateway cleanly.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        ca-certificates \
        tini \
    && rm -rf /var/lib/apt/lists/*

# Non-root user. UID 1000 matches the typical host user, which keeps
# bind-mounted ~/.openclaw permissions sane.
RUN useradd -m -s /bin/bash -u 1000 openclaw
USER openclaw
WORKDIR /home/openclaw

# Install OpenClaw globally under the user's npm prefix.
RUN npm config set prefix /home/openclaw/.npm-global \
    && PATH=/home/openclaw/.npm-global/bin:$PATH npm install -g openclaw@${OPENCLAW_VERSION}

ENV PATH=/home/openclaw/.npm-global/bin:$PATH \
    OPENCLAW_HIDE_BANNER=1 \
    OPENCLAW_SKIP_GMAIL_WATCHER=1 \
    OPENCLAW_SKIP_CANVAS_HOST=1 \
    OPENCLAW_DISABLE_BONJOUR=1

# Fail fast on a broken install.
RUN openclaw --version

# Default gateway port. Loopback inside the container; not exposed.
EXPOSE 18789

# Mount points expected at runtime:
#   /home/openclaw/.openclaw -> host ~/.openclaw (config + auth state, rw)
#
# Required env vars at runtime:
#   SLACK_BOT_TOKEN          - Slack bot user OAuth token (xoxb-...)
#   SLACK_APP_TOKEN          - Slack app-level token (xapp-...)
#   OPENCLAW_GATEWAY_TOKEN   - random token for gateway auth
#   GITHUB_PAT               - fine-grained PAT for dr-clankenstein-runs
ENTRYPOINT ["/usr/bin/tini", "--", "openclaw", "gateway"]
