ARG OPENCLAW_BASE_IMAGE=openclaw-base:local
FROM ${OPENCLAW_BASE_IMAGE}

USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash \
        build-essential \
        git-lfs \
        jq \
        openssh-client \
        openssh-server \
        python3-pip \
        python3-venv \
        ripgrep \
        rsync \
        unzip \
        wget \
        zip \
    && rm -f /etc/ssh/ssh_host_* \
    && mkdir -p /run/sshd \
    && chmod 0755 /run/sshd \
    && rm -rf /var/lib/apt/lists/*

COPY container/entrypoint.sh /usr/local/bin/agent-entrypoint
COPY container/git-askpass.sh /usr/local/bin/agent-git-askpass

RUN chmod 0755 /usr/local/bin/agent-entrypoint /usr/local/bin/agent-git-askpass \
    && mkdir -p /opt/agent-plugins \
    && ln -s /app/extensions/slack /opt/agent-plugins/slack

USER node

ARG IMAGE_REVISION=unknown
LABEL org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.title="Research agent runtime"

ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/usr/local/bin/agent-entrypoint"]
CMD ["check"]
