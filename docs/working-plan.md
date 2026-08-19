# Research agent box: working plan

Status: local implementation and EX3 login-node validation are functional as of 2026-08-19. Slurm GPU validation of the new image variants is pending.

## Objective

Build one self-contained research-agent repository that runs the same way on a
laptop, directly on EX3, or inside a Slurm job.

The agent must be able to:

- communicate with Preben through one Slack app in one private channel;
- use the internet;
- run arbitrary commands and subprocesses inside its box;
- read and write freely inside its box;
- use visible CPUs and GPUs;
- write one persistent mounted directory; and
- push to one GitHub repository with an expendable fine-grained token.

It must not be able to read or write other host files. In particular, the
model-controlled tools must not be able to read Codex OAuth state.

## Minimum architecture

One selected immutable image variant is started as two separate Apptainer instances:

```text
Slack <-> gateway <-> OpenAI
            |
            | tool calls over a local authenticated connection
            v
          worker
```

The split is required because one unrestricted process cannot keep a readable
OAuth token secret from itself.

### Gateway

The gateway:

- holds the Slack app and bot tokens;
- holds Codex OAuth state;
- receives Slack messages and sends replies;
- makes model requests;
- reads the user-written Markdown instructions;
- has no research workspace and no GitHub output token; and
- provides no model-controlled shell or file access in the gateway.

OpenClaw must own the model tool loop. The native Codex app-server runtime is
not used for agent turns.

### Worker

The worker is the agent's box. It receives:

- a writable temporary container filesystem;
- the persistent research workspace as its only writable host mount;
- unrestricted shell, process and file operations inside the box;
- internet access and optional GPU passthrough; and
- the fine-grained GitHub token for the agent's output repository.

It does not receive Slack tokens, Codex OAuth state, the host `.env`, host home,
or the host's container-registry credentials.

The worker is not restricted by a command allowlist. OpenClaw uses its full
tool profile. Only capabilities whose purpose is to execute outside the worker
or control external hosts are unavailable, including elevated gateway
execution and external-node control.

## Containment

Apptainer runs with containment enabled and with automatic host-home,
current-directory, host-filesystem and administrator bind mounts disabled.
Every host mount is explicit.

Apptainer normally shares the host network. The agent can therefore contact
the public internet, private networks reachable from the host, and listening
localhost services. This is accepted for the first implementation. The design
isolates files, credentials, environment and processes; it does not promise a
network firewall.

## Software and image policy

No OpenClaw, model, plugin or image version is selected by this design.

At implementation time:

1. Inspect the latest stable documentation, release notes, source and tests.
2. Select the latest stable versions that provide the required supported path.
3. Verify the behavior from clean state.
4. Only then record exact software versions, source commits and the immutable
   image digest for reproducibility.

GitHub Actions builds and publishes private OCI images. Laptop and EX3 hosts
pull immutable images with a host-only registry credential and convert them to
SIF files. Docker is used only by GitHub Actions, not on the laptop or EX3.

The runtime has three variants built from the same pinned OpenClaw source and
agent files:

- `cuda-amd64` for x86-64 NVIDIA nodes and x86-64 CPU-only use;
- `cuda-arm64` for ARM64 NVIDIA nodes and ARM64 CPU-only use; and
- `rocm-amd64` for x86-64 AMD nodes.

The launcher chooses one variant from the host architecture and `AGENT_GPU`,
then uses that same SIF for both gateway and worker. A declared architecture or
GPU-mode mismatch fails before worker startup. Actual GPU access is probed in
the worker before the Slack gateway starts. The CUDA children are also
published under one multi-platform OCI index; the launcher pins each child
digest explicitly. The ROCm variant includes a pinned PyTorch ROCm wheel and
its startup probe performs a real tensor computation.

Current common runtime selection, verified on 2026-08-19:

- OpenClaw release `v2026.7.1-2`, package version `2026.7.1`, source commit
  `0790d9f593ad30c940ed93b5872a8cf6d6f3cf8c`;
- OpenAI model `openai/gpt-5.6-sol`; and
- Apptainer `1.5.3` in local WSL and `1.5.0` on EX3.

The variant build selection being implemented is NVIDIA for `linux/amd64` and
`linux/arm64`, plus ROCm `6.2.4` and PyTorch `2.6.0` for `linux/amd64`. The
ROCm version matches the EX3 module selected for the first AMD test; the
resulting image and GPU execution still require build and Slurm verification.

Local proof completed on 2026-08-19:

- the OpenClaw runtime handled a real model turn;
- gateway startup reported the memory and Slack runtime plugins and performed
  no package installation;
- no unrelated bundled skills were injected, while the full worker tool profile
  remained available;
- model-controlled `read`, `write` and `edit` calls ran in the worker and wrote
  the persistent workspace;
- the worker reached the internet and the configured GitHub repository;
- the model fetched the `python/cpython` GitHub API record from the worker;
- the model created a workspace-local Python environment, installed CuPy, and
  completed a verified 256 by 256 matrix multiplication on the laptop GPU;
- the model committed and pushed the two smoke-test files to the configured
  repository, and the remote commit was independently verified;
- the gateway/worker credential and mount probes passed;
- the Markdown prompt report showed no truncation;
- the Slack Socket Mode connection reached ready state; and
- stopping the launcher removed both containers and both listeners.

Still pending: a background-process test, a deliberate model-led credential
search, and Slurm tests of the three image variants including cluster GPU
passthrough.

## Credentials

Each agent has:

- one Slack app;
- one private Slack channel;
- one Slack app token and one Slack bot token; and
- one fine-grained GitHub token limited to its output repository.

Codex OAuth belongs only to the gateway installation. Container-registry read
credentials belong only to the host and are never mounted into either
instance.

## Launch workflow

The repository has one launcher. Its run command is identical everywhere:

```text
laptop:        ./agent run
EX3 directly:  ./agent run
Slurm:         agent.sbatch calls ./agent run
```

The launcher never submits a Slurm job. Preben owns and edits the batch file,
including partition, node, GPU, CPU, memory and wall-time directives, and
submits it manually.

## Implementation sequence

1. Audit current stable OpenClaw, Apptainer and OpenAI model behavior using
   documentation, source, tests and known issues.
2. Remove the native Codex agent runtime, experimental sandbox execution
   server and custom OpenClaw compatibility patch.
3. Configure the explicit OpenClaw embedded runtime with Codex OAuth.
4. Give the worker the full tool profile while disabling only paths that leave
   or control the box.
5. Keep one selected image variant per run, one launcher and the same local,
   EX3 and Slurm execution path.
6. Build a private immutable image in GitHub Actions.
7. Purge generated local test state and perform the Gradient Unmasking Slack
   app test from a clean installation.

## Acceptance tests

The replacement is not complete until a clean local test proves all of the
following:

1. Runtime status reports the OpenClaw embedded runtime, not the native Codex
   app-server runtime.
2. The agent can run arbitrary foreground and background commands, manipulate
   files, install user-space packages, use the internet and inspect available
   hardware inside the worker.
3. The agent can clone its output repository and push a test commit.
4. Files created by model-controlled tools appear in the worker workspace and
   nowhere in the gateway.
5. The worker cannot see Codex OAuth state, Slack tokens, the host `.env`, host
   home, registry credentials or an unmounted host canary file.
6. Stopping the worker makes shell and file tools fail. They must not fall back
   to gateway execution.
7. Exactly one instance is connected to the selected Slack app. One Slack
   message produces one top-level reply with no duplicate or hidden response.
8. The user-written Markdown files are present in the intended prompt context
   without silent truncation.
9. Stopping the launcher leaves no gateway, worker or listener running.

Documentation states intended behavior. Source inspection and these tests are
required to establish actual behavior.
