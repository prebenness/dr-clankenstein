ARG OPENCLAW_BASE_IMAGE=openclaw-base:local
FROM ${OPENCLAW_BASE_IMAGE}

ARG OPENCLAW_VERSION

USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash \
        build-essential \
        dropbear-bin \
        git-lfs \
        jq \
        openssh-client \
        python3-pip \
        python3-venv \
        ripgrep \
        rsync \
        unzip \
        wget \
        zip \
    && rm -rf /var/lib/apt/lists/*

COPY container/entrypoint.sh /usr/local/bin/agent-entrypoint
COPY container/git-askpass.sh /usr/local/bin/agent-git-askpass

RUN chmod 0755 /usr/local/bin/agent-entrypoint /usr/local/bin/agent-git-askpass

RUN install -d -m 0755 -o node -g node /opt/openclaw-plugins

USER node

RUN set -eux; \
    test -n "$OPENCLAW_VERSION"; \
    OPENCLAW_STATE_DIR=/opt/openclaw-plugins/state \
    OPENCLAW_CONFIG_PATH=/opt/openclaw-plugins/state/openclaw.json \
        node /app/openclaw.mjs plugins install --pin "npm:@openclaw/slack@$OPENCLAW_VERSION"; \
    slack_dir="$(find /opt/openclaw-plugins/state -type d -path '*/node_modules/@openclaw/slack' -print -quit)"; \
    test -n "$slack_dir"; \
    ln -s "$slack_dir" /opt/openclaw-plugins/slack; \
    test -f /opt/openclaw-plugins/slack/openclaw.plugin.json; \
    test "$(node -p "require('/opt/openclaw-plugins/slack/package.json').version")" = "$OPENCLAW_VERSION"

ARG IMAGE_REVISION=unknown
LABEL org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.title="Research agent runtime"

ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/usr/local/bin/agent-entrypoint"]
CMD ["check"]
