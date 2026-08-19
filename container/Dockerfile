ARG OPENCLAW_BASE_IMAGE=openclaw-base:local
FROM ${OPENCLAW_BASE_IMAGE}

ARG IMAGE_VARIANT=unknown
ARG TARGETARCH=unknown
ARG ROCM_VERSION=6.2.4
ARG PYTORCH_ROCM_VERSION=2.6.0

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
        python3-setuptools \
        python3-venv \
        python3-wheel \
        ripgrep \
        rsync \
        unzip \
        wget \
        zip \
    && rm -f /etc/ssh/ssh_host_* \
    && mkdir -p /run/sshd \
    && chmod 0755 /run/sshd \
    && rm -rf /var/lib/apt/lists/*

RUN if [ "$IMAGE_VARIANT" = rocm-amd64 ]; then \
        python3 -m pip install \
            --break-system-packages \
            --no-cache-dir \
            "torch==${PYTORCH_ROCM_VERSION}" \
            --index-url "https://download.pytorch.org/whl/rocm${ROCM_VERSION}"; \
    fi

COPY container/entrypoint.sh /usr/local/bin/agent-entrypoint
COPY container/git-askpass.sh /usr/local/bin/agent-git-askpass

RUN chmod 0755 /usr/local/bin/agent-entrypoint /usr/local/bin/agent-git-askpass \
    && mkdir -p /opt/agent-plugins \
    && ln -s /app/extensions/slack /opt/agent-plugins/slack

USER node

ARG IMAGE_REVISION=unknown
ENV AGENT_IMAGE_VARIANT="${IMAGE_VARIANT}" \
    AGENT_IMAGE_ARCH="${TARGETARCH}"
LABEL org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.title="Research agent runtime" \
      org.opencontainers.image.architecture="${TARGETARCH}" \
      org.opencontainers.image.variant="${IMAGE_VARIANT}"

ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/usr/local/bin/agent-entrypoint"]
CMD ["check"]
