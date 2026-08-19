# Research agent box

This repository contains one research agent. The tracked Markdown files define its behaviour. The ignored `.agent/` directory contains its local state and persistent research workspace.

## Runtime boundary

The selected immutable image variant runs as two separate Apptainer instances:

| Instance | Receives | Does not receive |
| --- | --- | --- |
| Gateway | Slack tokens, Codex OAuth state, Markdown instructions, SSH client key | Research workspace, GitHub output token |
| Worker | Research workspace, fine-grained GitHub output token, SSH server key | Slack tokens, Codex OAuth state, host files |

OpenClaw and the Slack connection run in the gateway. Model-controlled shell, process and file tools are sent over a loopback SSH connection to the worker. The model does not receive a shell in the gateway.

OpenClaw owns the model loop and uses the selected OpenAI OAuth profile as its model transport. The native Codex app-server runtime and its experimental sandbox bridge are not enabled or used. The agent receives OpenClaw's full tool profile. Unrelated bundled skills are disabled; skills are prompt instructions, not tools. Only tools that control something outside the worker are denied: gateway control, external nodes, browser/canvas host control, and gateway cron. Slack communication remains available through the gateway. Shell execution inside the worker is unrestricted and does not require approvals.

The launcher reads `.env` on the host and gives each instance only its assigned variables. Temporary environment files are removed after process startup. Apptainer disables automatic host-home, current-directory, host-filesystem and administrator bind mounts. The worker's only persistent writable mount is `.agent/workspace/`. A generated copy of `/etc/resolv.conf` is mounted read-only to provide DNS.

Both instances use the host network stack for outbound access. The design isolates host files, credentials, environment and processes. It does not filter network destinations.

## Image

GitHub Actions builds the OCI images. This is the only place Docker is used. A laptop or EX3 installation needs Apptainer and does not need Docker, OpenClaw, npm or Codex installed on the host.

The manual `Build agent images` workflow:

1. Checks out the selected stable OpenClaw release and verifies its exact commit on each native build host.
2. Builds `cuda-amd64`, `cuda-arm64` and `rocm-amd64` from the same OpenClaw source and agent files.
3. Publishes the three immutable images and a two-platform CUDA index under `ghcr.io/prebenness/dr-clankenstein-runtime-v2` using the `GHCR_PUBLISH_TOKEN` Actions secret.
4. Refuses an existing package unless GitHub reports it as private.
5. Verifies the published package is private and rejects anonymous manifest access.
6. Prints all immutable image digests in the workflow summary.

`GHCR_PUBLISH_TOKEN` must be a classic GitHub personal access token with `read:packages` and `write:packages`, and no repository scope. The same token can authenticate host-side pulls. The workflow deliberately does not use the public source repository's `GITHUB_TOKEN`, because a package published from it can inherit the public repository's visibility.

The release is selected when the images are built, then its tag, source commit, package version, ROCm base and resulting image digests are pinned for reproducibility. Runtime startup never installs or updates packages. After a successful build, put the three reported `docker://...@sha256:...` references in `image.lock`.

The launcher selects exactly one variant for both instances:

| Compute node | `AGENT_GPU` | Variant |
| --- | --- | --- |
| x86-64 NVIDIA or CPU-only | `nv` or `none` | `cuda-amd64` |
| ARM64 NVIDIA or CPU-only | `nv` or `none` | `cuda-arm64` |
| x86-64 AMD | `rocm` | `rocm-amd64` |

The CUDA images contain the common research runtime and use Apptainer's NVIDIA passthrough. The ROCm image adds the pinned ROCm user-space runtime and PyTorch ROCm wheel, then uses Apptainer's AMD passthrough. A declared architecture or GPU-mode mismatch fails before worker startup. Actual device and runtime access is tested in the worker before the Slack gateway starts; the ROCm test includes a real PyTorch tensor computation.

The current architecture and acceptance tests are recorded in `docs/working-plan.md`.

## Credentials

| Credential | Quantity | Location | Visible to |
| --- | --- | --- | --- |
| GHCR registry PAT | One shared token | GitHub Actions secret and each host's Apptainer auth file | Image workflow and host-side `pull` only |
| Slack bot and app tokens | One pair per agent | `.env` | Gateway |
| Fine-grained output-repository PAT | One per agent | `.env` | Worker |
| Codex OAuth state | One login per installation | `.agent/gateway-state/` | Gateway |

Use that registry token to authenticate once on each machine:

```bash
# Laptop WSL or EX3 login node; any directory.
mkdir -p "$HOME/.apptainer"
printf '%s' "$GHCR_TOKEN" | apptainer registry login \
  --authfile "$HOME/.apptainer/agent-registry-auth.json" \
  --username YOUR_GITHUB_USER \
  --password-stdin docker://ghcr.io
unset GHCR_TOKEN
```

The launcher uses that explicit auth file when it pulls the private image. This avoids Docker Desktop credential helpers under WSL. The file is never mounted into either agent instance.

## New agent

Use a clone in a Linux filesystem. On Windows, clone under the WSL home directory rather than `/mnt/c`.

1. Write `AGENTS.md`, `SOUL.md`, `USER.md` and `HEARTBEAT.md`.
2. Create one Slack app from `slack-app-manifest.json` and add it to one private channel.
3. Create one fine-grained GitHub token with access only to the agent's output repository.
4. Create `.env` from the example and enter the credentials and identifiers.
5. Run the four launcher commands below.

```bash
# Laptop WSL; repository root.
cp .env.example .env
chmod 600 .env
./agent pull
./agent auth
./agent validate
./agent run
```

`auth` performs one interactive Codex device login. `validate` checks configuration, model authentication, required plugins, Slack startup, internet access, repository access, long SSH commands and the gateway/worker mount boundary. `run` stays in the foreground and stops both instances on `Ctrl-C`.

On the EX3 login node, use `./agent pull all` to stage all three SIF files after `image.lock` contains the completed build's three digests. Apptainer can pull the ARM image there without executing it. The launcher keeps Apptainer's cache and conversion temporary files under `.agent/`, so EX3 stores them on D1 with the checkout rather than in the small home filesystem. Run `./agent auth` and `./agent validate` on the login node, but run the long-lived agent only inside a Slurm allocation.

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

Before submitting, inspect which GPU partitions currently fit those resources:

```bash
# EX3 login node; repository root.
./free-gpus.sh
```

The command reads `agent.sbatch` by default, including a literal `AGENT_GPU=nv` or `AGENT_GPU=rocm` setting, and reports the compatible runtime variant for each partition. Use `--runtime cuda-amd64`, `--runtime cuda-arm64` or `--runtime rocm-amd64` to filter explicitly. Use `--verbose` for pending-job details and Slurm's `sbatch --test-only` response.

The batch file runs the same `./agent run` command used directly. Set `AGENT_GPU=nv` for NVIDIA, `AGENT_GPU=rocm` for AMD and `AGENT_GPU=none` for CPU-only use. The ROCm variant includes pinned PyTorch for immediate AMD compute. Other project-specific Python packages belong in the worker workspace.

Under WSL, NVIDIA passthrough additionally requires `nvidia-container-toolkit` on the host. The launcher then uses Apptainer's WSL-specific `--nvccli` path and mounts the host CUDA runtime library directory read-only. Native Linux hosts, including EX3, continue to use ordinary `--nv` passthrough.

## Local files

```text
.env                         host-side agent credentials
.agent/gateway-state/        OpenClaw sessions and Codex OAuth state
.agent/workspace/            worker's persistent writable directory
.agent/images/               immutable SIF files, one per runtime variant
.agent/apptainer-cache/      host-side OCI layer cache used while pulling
.agent/apptainer-tmp/        host-side SIF conversion temporary files
.agent/logs/                 gateway, worker and scheduler logs
AGENTS.md, SOUL.md, ...      user-written agent instructions
```

Do not copy `.agent/gateway-state/` into the worker workspace. It contains the protected Codex OAuth state.
