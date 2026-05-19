# dr-clankenstein

Autonomous research-agent container built on OpenClaw, deployed to the EX3 Slurm cluster as a 24-hour batch job.

## Build the container image (cluster-native)

The deployed `.sif` lives at `~/D1/containers/agent.sif`. Rebuild it when the OpenClaw version or build dependencies change.

From `~/D1/workspace/dr-clankenstein` on the cluster:

```bash
module use /cm/shared/ex3-modules/latest/modulefiles
module load apptainer/1.4.5
apptainer build --fakeroot ~/agent-new.sif Apptainer.def
mv ~/D1/containers/agent.sif ~/D1/containers/agent.sif.bak
mv ~/agent-new.sif ~/D1/containers/agent.sif
```

`--fakeroot` is required because `%post` runs `apt-get` inside the build. EX3 has user-namespace fakeroot enabled; drop the flag only if it errors with a subuid/subgid message.

The OpenClaw version is hardcoded in `Apptainer.def` and mirrored in `Dockerfile` for parity. To bump it, edit both files and rebuild.

## Deploy

From `~/D1/workspace/dr-clankenstein`:

```bash
sbatch cluster.sbatch
squeue -u prebenmn
```

## Secrets

Four env vars are needed at runtime: `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, `OPENCLAW_GATEWAY_TOKEN`, `GITHUB_PAT`. They are held in `~/dr-clankenstein.env` on the cluster (referenced by the sbatch via `--env-file`). Codex OAuth state lives in `~/.openclaw/openclaw.json`; re-run `openclaw models auth login --provider openai-codex` after overwriting that file.
