# Research agent box

This repository contains one research agent. Its Markdown files define the agent. Its local `.agent/` directory contains that agent's persistent state and workspace.

## Design

The same image runs twice:

| Process | Receives | Does not receive |
| --- | --- | --- |
| Gateway | Slack tokens, Codex OAuth state, prompt files, SSH client key | Research workspace, GitHub token |
| Worker | Research workspace, fine-grained GitHub token, SSH server key | Slack tokens, Codex OAuth state |

OpenClaw runs in the gateway. Every model-controlled shell and file operation is sent over the private loopback SSH connection to the worker. The `.env` file is read by the launcher and split into two temporary environment files; it is not mounted into either process.

Apptainer starts both processes with host home, current directory, configured host filesystems, and administrator bind paths disabled. The only persistent writable mounts are gateway state and the worker workspace. Both processes retain outbound network access.

## Image

GitHub Actions builds the image from a pinned OpenClaw commit. It installs the bundled Codex and Slack plugins and then adds the small worker toolset in `container/`.

The workflow publishes a private `linux/amd64` image to this repository's GitHub Container Registry package. Its job summary prints an immutable `docker://...@sha256:...` reference. Put that reference in `image.lock` after each intentional image rebuild.

Image publication uses the workflow's `GITHUB_TOKEN`. It does not use an agent token.

Each machine needs one GitHub classic personal access token with `read:packages` to pull private images:

```bash
# Laptop WSL or EX3 login node; any directory.
printf '%s' "$GHCR_READ_TOKEN" | apptainer registry login \
  --username YOUR_GITHUB_USER \
  --password-stdin docker://ghcr.io
unset GHCR_READ_TOKEN
```

This machine credential stays in Apptainer's registry configuration. It is not passed to an agent. The per-agent fine-grained token only needs access to that agent's output repository.

## New Agent

Run these commands inside a Linux filesystem. On Windows, use a fresh clone under the WSL home directory rather than `/mnt/c`.

```bash
# Laptop WSL or EX3 login node; repository root.
cp .env.example .env
chmod 600 .env
```

Edit `.env`. Supply one Slack app's bot and app tokens, its channel ID, your Slack user ID, and one expendable fine-grained GitHub token. `GITHUB_REPOSITORY` may be left empty for a communication-only test.

```bash
# Laptop WSL or EX3 login node; repository root.
./agent pull
./agent init
./agent auth
./agent validate
./agent run
```

`./agent auth` performs the one interactive Codex device login. `./agent run` stays in the foreground. Stop it with `Ctrl-C`.

## Slurm

The launcher never submits a job. Create and edit your own ignored copy:

```bash
# EX3 login node; repository root.
cp agent.sbatch.example agent.sbatch
```

Set the partition, node constraint, GPU count, CPUs, memory, wall time, and `AGENT_GPU` in `agent.sbatch`. Then submit it yourself:

```bash
# EX3 login node; repository root.
./agent init
sbatch agent.sbatch
```

The batch script runs the same `./agent run` command used directly on a laptop or compute node. Use `AGENT_GPU=nv` for NVIDIA, `AGENT_GPU=rocm` for AMD, and `AGENT_GPU=none` for CPU-only use. The first image deliberately excludes ARM hosts and large machine-learning stacks.

## Local Files

```text
.env                         host-side agent credentials
.agent/gateway-state/        OpenClaw sessions and Codex OAuth state
.agent/workspace/            the worker's only persistent writable directory
.agent/logs/                 launcher, gateway, and worker logs
AGENTS.md, SOUL.md, ...      user-written agent instructions
```

Do not copy `.agent/gateway-state/` into the worker workspace. It contains the protected Codex OAuth state.
