# Simula Agent Container Design

Status: draft.

## Scope

This project provides a maintained container environment for agentic coding at Simula.

V1 supports four profiles:

| | Local | EX3 |
| --- | --- | --- |
| Codex CLI | Interactive CLI in a rootless Podman container | Interactive CLI in Apptainer inside a Slurm allocation |
| OpenClaw with Slack | Slack-facing agent in a rootless Podman container | Slack-facing agent in Apptainer inside a Slurm job |

Codex CLI is the direct terminal interface. OpenClaw is the Slack-facing agent interface. EX3 always runs through Slurm.

V1 targets CUDA on amd64. This covers local Linux workstations with Nvidia GPUs and the main EX3 Nvidia partitions.

## EX3 Codex CLI

The EX3 Codex CLI profile is interactive.

```text
ssh to EX3 login node
start interactive Slurm allocation
Slurm starts Apptainer
Apptainer starts Codex CLI
user works in the Codex terminal session
```

This gives the same interaction model as local Codex CLI, with EX3 resource accounting and container isolation.

## Runtime Contract

Each run has:

- owner;
- project;
- profile;
- workspace;
- state directory;
- image;
- resource request;
- credentials;
- logs;
- stop command.

The runner records these fields at startup.

Local profiles mount one writable workspace and one writable state directory. Credentials are injected explicitly.

## Image Strategy

V1 has one image:

```text
simula-agent-cuda-amd64:<version>
```

The image contains:

- Codex CLI;
- OpenClaw;
- the OpenClaw Slack integration;
- CUDA-compatible runtime support;
- the entrypoint dispatcher.

The same image serves all four profiles. Runtime profile selection decides whether the container starts Codex CLI or OpenClaw.

Images use immutable versioned tags, for example:

```text
simula-agent-cuda-amd64:2026.07.0
```

The runner may resolve `stable` for convenience, but run records store the immutable image identifier.

Local users consume the OCI image through Podman. EX3 uses the corresponding Apptainer SIF from a managed shared location. The EX3 runner resolves the SIF path from an image manifest.

## Hardware Mapping

V1 maps to CUDA amd64 hardware.

| Target | Image |
| --- | --- |
| Local Linux amd64 with Nvidia GPU | `simula-agent-cuda-amd64:<version>` |
| EX3 `a100q`, `dgx2q`, `hgx2q`, `h200q` | `simula-agent-cuda-amd64:<version>` |

The hardware mapping belongs in one runner module or manifest.

## Security Baseline

The container boundary is defined by explicit mounts and explicit credentials.

Local profiles mount:

- the selected workspace, writable;
- the selected state directory, writable;
- required read-only project guidance files, when present.

EX3 profiles mount:

- the selected workspace, writable;
- the selected state directory, writable;
- required read-only project guidance files, when present;
- Slurm-provided GPU resources.

The container image is immutable during normal use. Generated code remains hazardous and requires review.

## Records, Ownership, And Stops

Each run records owner, project, profile, image identifier, workspace path, state path, model or provider setting, start time, stop time when known, Slurm job id when on EX3, log path, and stop command.

Each project records human owner, project identifier, allowed workspace, allowed credentials, profile, and model provider.

| Profile | Stop path |
| --- | --- |
| Local Codex CLI | Exit Codex and stop the Podman container |
| Local OpenClaw with Slack | Stop the named Podman container |
| EX3 Codex CLI | Cancel the interactive Slurm job |
| EX3 OpenClaw with Slack | Cancel the Slurm job and rotate affected credentials when needed |

A writable workspace has one active agent at a time. The runner warns when an active run record exists for the selected workspace.

## V1 Acceptance Criteria

1. Local Codex CLI runs interactively in a rootless Podman container on a Linux amd64 workstation with an Nvidia GPU.
2. EX3 Codex CLI runs interactively inside Slurm and Apptainer on a CUDA amd64 partition.
3. Local OpenClaw with Slack starts in a rootless Podman container.
4. EX3 OpenClaw with Slack starts as a Slurm job.
5. The same image serves all four profiles.
6. Each run records owner, image, workspace, state, location, and stop information.

## V1 Work Plan

1. Define the profile schema.
2. Add Codex CLI to the shared CUDA amd64 image.
3. Add an entrypoint dispatcher for Codex CLI, OpenClaw, shell, and preflight.
4. Add the local Podman runner.
5. Add the EX3 interactive Slurm runner for Codex CLI.
6. Preserve the existing EX3 OpenClaw Slurm path.
7. Add the local OpenClaw runner.
8. Add run records and project manifests.
9. Write one user guide per supported profile.
