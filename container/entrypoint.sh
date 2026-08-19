#!/usr/bin/env bash
set -Eeuo pipefail

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
[[ ! -d /opt/rocm/bin ]] || PATH="/opt/rocm/bin:$PATH"
export PATH

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

keygen() {
    local port="${1:?worker port is required}"
    local gateway_dir=/bridge/gateway
    local worker_dir=/bridge/worker
    local worker_home="$worker_dir/home"
    local host_public

    mkdir -p "$gateway_dir" "$worker_home/.ssh" "$worker_home/.openclaw/workspace"
    chmod 0700 "$gateway_dir" "$worker_dir" "$worker_home" "$worker_home/.ssh"
    chmod 0755 "$worker_home/.openclaw" "$worker_home/.openclaw/workspace"

    if [[ ! -f "$gateway_dir/client_key" ]]; then
        ssh-keygen -q -t ed25519 -N '' -C agent-bridge -f "$gateway_dir/client_key"
    fi
    if [[ ! -f "$gateway_dir/client_key.pub" ]]; then
        ssh-keygen -y -f "$gateway_dir/client_key" > "$gateway_dir/client_key.pub"
    fi
    if [[ ! -f "$worker_dir/ssh_host_key" ]]; then
        ssh-keygen -q -t ed25519 -N '' -C agent-worker -f "$worker_dir/ssh_host_key"
    fi

    printf '%s %s\n' \
        'no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty,command="/usr/local/bin/agent-entrypoint worker-shell"' \
        "$(cat "$gateway_dir/client_key.pub")" \
        > "$worker_home/.ssh/authorized_keys"

    host_public="$(ssh-keygen -y -f "$worker_dir/ssh_host_key")"
    [[ -n "$host_public" ]] || die 'could not derive the worker SSH host key'
    printf '[127.0.0.1]:%s %s\n' "$port" "$host_public" > "$gateway_dir/known_hosts"

    chmod 0600 \
        "$gateway_dir/client_key" \
        "$gateway_dir/known_hosts" \
        "$worker_dir/ssh_host_key" \
        "$worker_home/.ssh/authorized_keys"
    chmod 0644 "$gateway_dir/client_key.pub"
    [[ ! -f "$worker_dir/ssh_host_key.pub" ]] || chmod 0644 "$worker_dir/ssh_host_key.pub"
}

worker_shell() {
    local worker_env=/tmp/agent-worker/environment

    [[ -r "$worker_env" ]] || die 'worker environment is missing'
    # shellcheck disable=SC1090
    source "$worker_env"
    [[ "${AGENT_BOX_ROLE:-}" == worker ]] || die 'worker shell started outside the worker'

    unset SLACK_BOT_TOKEN SLACK_APP_TOKEN OPENCLAW_GATEWAY_TOKEN CODEX_HOME

    export HOME=/tmp/agent-home
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_DATA_HOME="$HOME/.local/share"
    export GIT_ASKPASS=/usr/local/bin/agent-git-askpass
    export GIT_ASKPASS_REQUIRE=force
    export GIT_TERMINAL_PROMPT=0
    export PIP_CACHE_DIR="$HOME/.cache/pip"
    mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
    chmod 0700 "$HOME"

    if [[ -z "${SSH_ORIGINAL_COMMAND:-}" ]]; then
        exec /bin/bash --noprofile --norc
    fi
    exec /bin/bash --noprofile --norc -c "$SSH_ORIGINAL_COMMAND"
}

write_worker_shell_env() {
    local name
    local worker_dir=/tmp/agent-worker
    local worker_env="$worker_dir/environment"

    umask 077
    mkdir -p "$worker_dir"
    : > "$worker_env"
    for name in \
        AGENT_BOX_ROLE \
        GITHUB_PAT \
        GITHUB_REPOSITORY \
        CUDA_VISIBLE_DEVICES \
        NVIDIA_VISIBLE_DEVICES \
        CUDA_DEVICE_ORDER \
        ROCR_VISIBLE_DEVICES \
        HIP_VISIBLE_DEVICES \
        GPU_DEVICE_ORDINAL \
        LD_LIBRARY_PATH \
        SSL_CERT_FILE \
        NODE_EXTRA_CA_CERTS \
        REQUESTS_CA_BUNDLE \
        GIT_SSL_CAINFO \
        CURL_CA_BUNDLE; do
        [[ -v "$name" ]] || continue
        printf 'export %s=%q\n' "$name" "${!name}" >> "$worker_env"
    done
    chmod 0600 "$worker_env"
}

worker() {
    local port="${AGENT_WORKER_PORT:?AGENT_WORKER_PORT is required}"
    local login_home
    [[ "${AGENT_BOX_ROLE:-}" == worker ]] || die 'AGENT_BOX_ROLE must be worker'
    [[ -n "${GITHUB_PAT:-}" ]] || die 'GITHUB_PAT is missing from the worker environment'
    [[ -r /run/agent-bridge/ssh_host_key ]] || die 'worker SSH host key is not mounted'
    login_home="$(getent passwd "$(id -u)" | cut -d: -f6)"
    write_worker_shell_env

    exec /usr/sbin/sshd -D -e -f /dev/null \
        -h /run/agent-bridge/ssh_host_key \
        -p "$port" \
        -o ListenAddress=127.0.0.1 \
        -o PidFile=/tmp/agent-sshd.pid \
        -o "AuthorizedKeysFile=$login_home/.ssh/authorized_keys" \
        -o PasswordAuthentication=no \
        -o KbdInteractiveAuthentication=no \
        -o UsePAM=no \
        -o PermitRootLogin=no \
        -o AllowAgentForwarding=no \
        -o AllowTcpForwarding=no \
        -o X11Forwarding=no \
        -o PermitTunnel=no \
        -o PermitTTY=no \
        -o StrictModes=yes \
        -o LogLevel=ERROR
}

gateway() {
    [[ "${AGENT_BOX_ROLE:-}" == gateway ]] || die 'AGENT_BOX_ROLE must be gateway'
    export HOME=/home/node
    export OPENCLAW_STATE_DIR=/home/node/.openclaw
    export OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json
    cd /app
    exec node /app/openclaw.mjs gateway "$@"
}

openclaw_cli() {
    export HOME=/home/node
    export OPENCLAW_STATE_DIR=/home/node/.openclaw
    export OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json
    cd /app
    exec node /app/openclaw.mjs "$@"
}

worker_ssh() {
    local user="${1:?worker user is required}"
    local port="${2:?worker port is required}"
    shift 2

    ssh \
        -F /dev/null \
        -T \
        -p "$port" \
        -i /run/agent-bridge/client_key \
        -o BatchMode=yes \
        -o ConnectTimeout=2 \
        -o IdentitiesOnly=yes \
        -o LogLevel=ERROR \
        -o StrictHostKeyChecking=yes \
        -o UpdateHostKeys=no \
        -o UserKnownHostsFile=/run/agent-bridge/known_hosts \
        "$user@127.0.0.1" \
        "$@"
}

probe_worker() {
    local user="${1:?worker user is required}"
    local port="${2:?worker port is required}"
    local host_sentinel="${3:?host sentinel path is required}"
    local host_env_file="${4:?host environment path is required}"
    local host_private_file="${5:?host private file path is required}"
    local sentinel_q env_q private_q command

    printf -v sentinel_q '%q' "$host_sentinel"
    printf -v env_q '%q' "$host_env_file"
    printf -v private_q '%q' "$host_private_file"
    # These variables expand in the worker shell reached over SSH.
    # shellcheck disable=SC2016
    printf -v command '%s' \
        'test "${AGENT_BOX_ROLE:-}" = worker' \
        ' && test -n "${GITHUB_PAT:-}"' \
        ' && test -z "${SLACK_BOT_TOKEN:-}"' \
        ' && test -z "${SLACK_APP_TOKEN:-}"' \
        ' && test -z "${OPENCLAW_GATEWAY_TOKEN:-}"' \
        ' && test -z "${CODEX_HOME:-}"' \
        ' && test "$HOME" = /tmp/agent-home' \
        ' && test -w /home/node/.openclaw/workspace' \
        ' && test ! -e /gateway-workspace' \
        ' && test ! -e /home/node/.codex' \
        ' && test ! -e /home/node/.openclaw/agents' \
        ' && test ! -e /home/node/.openclaw/openclaw.json'
    command+=" && test ! -e $sentinel_q"
    command+=" && test ! -e $env_q"
    command+=" && test ! -e $private_q"
    command+=' && printf "worker boundary ok\\n"'

    worker_ssh "$user" "$port" "$command"
}

probe_worker_internet() {
    local user="${1:?worker user is required}"
    local port="${2:?worker port is required}"

    worker_ssh "$user" "$port" \
        'wget --quiet --spider --timeout=15 https://api.github.com/ && printf "worker internet ok\n"'
}

probe_worker_long_command() {
    local user="${1:?worker user is required}"
    local port="${2:?worker port is required}"
    local padding

    printf -v padding '%020000d' 0
    worker_ssh "$user" "$port" "printf 'worker long command ok\\n'; #$padding"
}

probe_worker_gpu() {
    local user="${1:?worker user is required}"
    local port="${2:?worker port is required}"
    local mode="${3:?GPU mode is required}"

    case "$mode" in
        nv)
            worker_ssh "$user" "$port" \
                'output="$(nvidia-smi -L 2>&1)" && test -n "$output" && printf "worker GPU ok (NVIDIA): %s\n" "${output%%$'\''\n'\''*}"'
            ;;
        rocm)
            worker_ssh "$user" "$port" \
                'test -c /dev/kfd && output="$(rocminfo 2>&1)" && grep -Eq "Device Type:[[:space:]]+GPU" <<<"$output" && python3 -c '\''import torch; assert torch.version.hip; assert torch.cuda.is_available(); x = torch.arange(16, device="cuda", dtype=torch.float32).reshape(4, 4); y = x @ x; assert y.shape == (4, 4); torch.cuda.synchronize(); print(f"worker GPU ok (ROCm/PyTorch): {torch.cuda.get_device_name(0)}")'\'''
            ;;
        *)
            die "unsupported GPU probe mode: $mode"
            ;;
    esac
}

probe_worker_repository() {
    local user="${1:?worker user is required}"
    local port="${2:?worker port is required}"
    local repository="${3:?repository is required}"
    local repository_q

    printf -v repository_q '%q' "$repository"
    worker_ssh "$user" "$port" \
        "test \"\${GITHUB_REPOSITORY:-}\" = $repository_q && git ls-remote \"https://github.com/\$GITHUB_REPOSITORY.git\" HEAD >/dev/null && printf 'worker repository ok\\n'"
}

probe_gateway() {
    local host_workspace="${1:?host workspace path is required}"
    local config="${OPENCLAW_CONFIG_PATH:-/home/node/.openclaw/openclaw.json}"

    [[ "${AGENT_BOX_ROLE:-}" == gateway ]] || die 'gateway role is missing'
    [[ -n "${SLACK_BOT_TOKEN:-}" ]] || die 'Slack bot token is missing from the gateway'
    [[ -n "${SLACK_APP_TOKEN:-}" ]] || die 'Slack app token is missing from the gateway'
    [[ -z "${GITHUB_PAT:-}" ]] || die 'GitHub token is visible in the gateway'
    [[ -w /home/node/.openclaw ]] || die 'gateway state is not writable'
    [[ -r /gateway-workspace/AGENTS.md ]] || die 'gateway instructions are not readable'
    [[ ! -w /gateway-workspace/AGENTS.md ]] || die 'gateway instructions are writable'
    [[ ! -e "$host_workspace" ]] || die 'worker workspace host path is visible in the gateway'
    jq -e '.agents.defaults.models["openai/gpt-5.6-sol"].agentRuntime.id == "openclaw"' \
        "$config" >/dev/null || die 'the OpenClaw embedded runtime is not selected'
    jq -e '.tools.profile == "full"' "$config" >/dev/null || die 'the full tool profile is not selected'
    jq -e '.tools.exec.host == "sandbox" and .tools.exec.mode == "full"' \
        "$config" >/dev/null || die 'worker shell execution is not unrestricted'
    jq -e '.agents.defaults.sandbox.mode == "all" and .agents.defaults.sandbox.backend == "ssh"' \
        "$config" >/dev/null || die 'the SSH worker sandbox is not mandatory'
    jq -e '.tools.elevated.enabled == false' "$config" >/dev/null || die 'elevated execution is enabled'
    jq -e '(.plugins.allow | index("codex")) == null' \
        "$config" >/dev/null || die 'the native Codex runtime plugin is still allowed'
    printf 'gateway boundary ok\n'
}

case "${1:-check}" in
    check)
        printf 'Runtime image %s (%s)\n' "${AGENT_IMAGE_VARIANT:-unknown}" "${AGENT_IMAGE_ARCH:-unknown}"
        if [[ "${AGENT_IMAGE_VARIANT:-}" == rocm-* ]]; then
            [[ -x /opt/rocm/bin/rocminfo ]] || die 'the ROCm runtime is missing from the image'
            [[ -e /opt/rocm/lib/libhsa-runtime64.so.1 ]] || die 'the ROCm HSA runtime is missing from the image'
            python3 -c 'import torch; assert torch.version.hip' || die 'the ROCm PyTorch runtime is missing from the image'
        fi
        [[ -f /opt/agent-plugins/slack/openclaw.plugin.json ]] ||
            die 'the Slack plugin is missing from the image'
        [[ -f /app/extensions/openai/openclaw.plugin.json ]] ||
            die 'the OpenAI provider plugin is missing from the image'
        node /app/openclaw.mjs --version
        git --version
        dpkg-query -W -f='OpenSSH server ${Version}\n' openssh-server
        ;;
    login-home)
        getent passwd "$(id -u)" | cut -d: -f6
        ;;
    login-user)
        getent passwd "$(id -u)" | cut -d: -f1
        ;;
    keygen)
        shift
        keygen "$@"
        ;;
    gateway)
        shift
        gateway "$@"
        ;;
    worker)
        shift
        worker "$@"
        ;;
    worker-shell)
        shift
        worker_shell "$@"
        ;;
    openclaw)
        shift
        openclaw_cli "$@"
        ;;
    probe-worker)
        shift
        probe_worker "$@"
        ;;
    probe-worker-internet)
        shift
        probe_worker_internet "$@"
        ;;
    probe-worker-long-command)
        shift
        probe_worker_long_command "$@"
        ;;
    probe-worker-gpu)
        shift
        probe_worker_gpu "$@"
        ;;
    probe-worker-repository)
        shift
        probe_worker_repository "$@"
        ;;
    probe-gateway)
        shift
        probe_gateway "$@"
        ;;
    *)
        die "unknown entrypoint command: $1"
        ;;
esac
