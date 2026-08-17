#!/usr/bin/env bash
set -Eeuo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

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
    if [[ ! -f "$worker_dir/host_key" ]]; then
        dropbearkey -t ed25519 -f "$worker_dir/host_key" >/dev/null
    fi

    printf '%s %s\n' \
        'no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty,command="/usr/local/bin/agent-entrypoint worker-shell"' \
        "$(cat "$gateway_dir/client_key.pub")" \
        > "$worker_home/.ssh/authorized_keys"

    host_public="$(dropbearkey -y -f "$worker_dir/host_key" 2>/dev/null | sed -n '/^ssh-/p' | head -n 1)"
    [[ -n "$host_public" ]] || die 'could not derive the worker SSH host key'
    printf '[127.0.0.1]:%s %s\n' "$port" "$host_public" > "$gateway_dir/known_hosts"

    chmod 0600 \
        "$gateway_dir/client_key" \
        "$gateway_dir/known_hosts" \
        "$worker_dir/host_key" \
        "$worker_home/.ssh/authorized_keys"
    chmod 0644 "$gateway_dir/client_key.pub"
}

worker_shell() {
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

worker() {
    local port="${AGENT_WORKER_PORT:?AGENT_WORKER_PORT is required}"
    [[ "${AGENT_BOX_ROLE:-}" == worker ]] || die 'AGENT_BOX_ROLE must be worker'
    [[ -n "${GITHUB_PAT:-}" ]] || die 'GITHUB_PAT is missing from the worker environment'
    [[ -r /run/agent-bridge/host_key ]] || die 'worker SSH host key is not mounted'

    exec dropbear \
        -F -E -e -m -s -g -w -j -k \
        -P /tmp/agent-dropbear.pid \
        -p "127.0.0.1:$port" \
        -r /run/agent-bridge/host_key
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

probe_worker() {
    local user="${1:?worker user is required}"
    local port="${2:?worker port is required}"

    exec ssh \
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
        'test "${AGENT_BOX_ROLE:-}" = worker && test -n "${GITHUB_PAT:-}" && test -z "${SLACK_BOT_TOKEN:-}" && test -z "${SLACK_APP_TOKEN:-}" && test -w /home/node/.openclaw/workspace && test ! -d /home/node/.openclaw/agents && printf "worker boundary ok\n"'
}

case "${1:-check}" in
    check)
        node /app/openclaw.mjs --version
        git --version
        dropbear -V
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
    *)
        die "unknown entrypoint command: $1"
        ;;
esac
