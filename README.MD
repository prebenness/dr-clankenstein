# Research agent box

This repository contains one research agent. The tracked Markdown files define its behaviour. The ignored `.agent/` directory contains its local state and persistent research workspace.

## Runtime boundary

The same immutable image runs as two separate Apptainer instances:

| Instance | Receives | Does not receive |
| --- | --- | --- |
| Gateway | Slack tokens, Codex OAuth state, Markdown instructions, SSH client key | Research workspace, GitHub output token |
| Worker | Research workspace, fine-grained GitHub output token, SSH server key | Slack tokens, Codex OAuth state, host files |

OpenClaw and the Slack connection run in the gateway. Model-controlled shell, process and file tools are sent over a loopback SSH connection to the worker. The model does not receive a shell in the gateway.

OpenClaw owns the model loop and uses the selected OpenAI OAuth profile as its model transport. The Codex app-server runtime and its experimental sandbox bridge are not used. The Codex package is present but excluded from `plugins.allow`; this satisfies OpenClaw's OAuth setup check without enabling that runtime or downloading it during setup. The agent receives OpenClaw's full tool profile. Only tools that control something outside the worker are denied: gateway control, external nodes, browser/canvas host control, gateway cron, and direct Slack plugin actions. Normal Slack replies still pass through the gateway. Shell execution inside the worker is unrestricted and does not require approvals.

The launcher reads `.env` on the host and gives each instance only its assigned variables. Temporary environment files are removed after process startup. Apptainer disables automatic host-home, current-directory, host-filesystem and administrator bind mounts. The worker's only persistent writable mount is `.agent/workspace/`. A generated copy of `/etc/resolv.conf` is mounted read-only to provide DNS.

Both instances use the host network stack for outbound access. The design isolates host files, credentials, environment and processes. It does not filter network destinations.

## Image

GitHub Actions builds the OCI image. This is the only place Docker is used. A laptop or EX3 installation needs Apptainer and does not need Docker, OpenClaw, npm or Codex installed on the host.

The manual `Build agent image` workflow:

1. Checks out the selected stable OpenClaw release, verifies its exact commit, and retains the required official plugin code in the image.
2. Publishes `ghcr.io/prebenness/dr-clankenstein-runtime-v2` using the `GHCR_PUBLISH_TOKEN` Actions secret.
3. Refuses an existing package unless GitHub reports it as private.
4. Verifies the published package is private and rejects anonymous manifest access.
5. Prints the immutable image digest in the workflow summary.

`GHCR_PUBLISH_TOKEN` must be a classic GitHub personal access token with `write:packages` and no repository scope. The workflow deliberately does not use the public source repository's `GITHUB_TOKEN` to publish the package.

The release is selected when the image is built, then its tag, source commit, package version and resulting image digest are pinned for reproducibility. Runtime startup never installs or updates packages. After a successful build, put the reported `docker://...@sha256:...` reference in `image.lock`.

The current architecture and acceptance tests are recorded in `docs/working-plan.md`.

## Credentials

| Credential | Quantity | Location | Visible to |
| --- | --- | --- | --- |
| GHCR publisher PAT | One shared token | GitHub Actions secret | Image workflow only |
| GHCR reader PAT | One shared token | Each host's Apptainer auth file | Host-side `pull` only |
| Slack bot and app tokens | One pair per agent | `.env` | Gateway |
| Fine-grained output-repository PAT | One per agent | `.env` | Worker |
| Codex OAuth state | One login per installation | `.agent/gateway-state/` | Gateway |

The GHCR reader token must be a classic PAT with `read:packages`. Authenticate once on each machine:

```bash
# Laptop WSL or EX3 login node; any directory.
mkdir -p "$HOME/.apptainer"
printf '%s' "$GHCR_READ_TOKEN" | apptainer registry login \
  --authfile "$HOME/.apptainer/agent-registry-auth.json" \
  --username YOUR_GITHUB_USER \
  --password-stdin docker://ghcr.io
unset GHCR_READ_TOKEN
```

The launcher uses that explicit auth file when it pulls the private image. This avoids Docker Desktop credential helpers under WSL. The file is never mounted into either agent instance.

## New agent

Use a clone in a Linux filesystem. On Windows, clone under the WSL home directory rather than `/mnt/c`.

1. Write `AGENTS.md`, `SOUL.md`, `USER.md` and `HEARTBEAT.md`.
2. Create one Slack app from `slack-app-manifest.json` and add it to one private channel.
3. Create one fine-grained GitHub token with access only to the agent's output repository.
4. Create `.env` from the example and enter the credentials and identifiers.
5. Run the five launcher commands below.

```bash
# Laptop WSL or EX3 login node; repository root.
cp .env.example .env
chmod 600 .env
./agent pull
./agent init
./agent auth
./agent validate
./agent run
```

`init` registers the Slack plugin already inside the image and does not contact npm. `auth` performs one interactive Codex device login. `validate` checks configuration, model authentication, required plugins, internet access, repository access and the gateway/worker mount boundary. `run` stays in the foreground and stops both instances on `Ctrl-C`.

To discard an installation's generated state while preserving its tracked files and `.env`:

```bash
# Laptop WSL or EX3; repository root. Stop the agent first.
rm -rf -- .agent
```

## Slurm

The launcher never submits a job. Create an ignored batch file and edit its resource directives yourself:

```bash
# EX3 login node; repository root.
cp agent.sbatch.example agent.sbatch
```

Set the partition, node constraint, GPU count, CPUs, memory, wall time and `AGENT_GPU`. Submit it yourself with `sbatch agent.sbatch`.

The batch file runs the same `./agent run` command used directly. Set `AGENT_GPU=nv` for NVIDIA, `AGENT_GPU=rocm` for AMD and `AGENT_GPU=none` for CPU-only use. The current image supports x86-64 hosts and deliberately excludes large machine-learning stacks.

## Local files

```text
.env                         host-side agent credentials
.agent/gateway-state/        OpenClaw sessions and Codex OAuth state
.agent/workspace/            worker's persistent writable directory
.agent/logs/                 gateway, worker and scheduler logs
AGENTS.md, SOUL.md, ...      user-written agent instructions
```

Do not copy `.agent/gateway-state/` into the worker workspace. It contains the protected Codex OAuth state.
