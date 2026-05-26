# dr-clankenstein

OpenClaw research-agent harness for EX3 Slurm jobs.

Run one isolated instance per research project:

- one Slack app and channel;
- one GitHub output repo;
- one `.env`;
- one workspace dir;
- one OpenClaw state dir;
- one source checkout;
- one gateway port.

Do not share Slack app tokens, workspace dirs, OpenClaw state dirs, or gateway ports between live agents.

## Build Image

Only needed when the container definition or OpenClaw version changes.

Run on EX3 from any `dr-clankenstein` checkout:

```bash
module use /cm/shared/ex3-modules/latest/modulefiles
module load apptainer/1.4.5
apptainer build --fakeroot ~/agent-new.sif Apptainer.def
mv ~/D1/containers/agent.sif ~/D1/containers/agent.sif.bak
mv ~/agent-new.sif ~/D1/containers/agent.sif
```

## New Project

Run on EX3. Replace `PROJECT` with a short id, for example `bnn-timeseries`.

```bash
cd ~/D1/workspace
git clone git@github.com:prebenness/dr-clankenstein.git dr-clankenstein-PROJECT
cd dr-clankenstein-PROJECT
cp .env.example .env
chmod 600 .env
nano .env
```

Fill `.env`. Use unique values for:

```text
CLANKENSTEIN_ID
SLACK_BOT_TOKEN
SLACK_APP_TOKEN
SLACK_CHANNEL_ID
RUNS_REPO_URL
RUNS_REPO_DIR
CLANKENSTEIN_WORKSPACE_DIR
CLANKENSTEIN_OPENCLAW_DIR
CLANKENSTEIN_GATEWAY_PORT
```

Generate `OPENCLAW_GATEWAY_TOKEN` with:

```bash
openssl rand -hex 32
```

Use an HTTPS output repo URL, for example:

```text
RUNS_REPO_URL=https://github.com/prebenness/PROJECT-runs.git
```

`GITHUB_PAT` must have contents read/write access to that output repo.

## Slack App

Use one Slack app per live agent. Do not reuse the same Slack app token for two running agents.

Create the app at `https://api.slack.com/apps`.

Required setup:

```text
Socket Mode: enabled
App-level token scope: connections:write
Bot scopes:
  app_mentions:read
  assistant:write
  channels:history
  channels:read
  chat:write
  commands
  groups:history
  groups:read
  im:history
  im:read
  im:write
  users:read
Bot events:
  app_home_opened
  app_mention
  assistant_thread_context_changed
  assistant_thread_started
  message.channels
  message.groups
  message.im
```

Install the app, invite it to the project channel, and put the channel id in `SLACK_CHANNEL_ID`.

OpenClaw Slack docs: `https://docs.openclaw.ai/channels/slack`.

## Setup And Auth

Run once per project from the project checkout on EX3:

```bash
bash setup-project.sh
bash auth-codex.sh login
```

`setup-project.sh` creates the workspace, OpenClaw state dir, rendered OpenClaw config, git helper, and `state/instance.json`.

`auth-codex.sh login` starts the manual Codex auth flow and stores auth in the project OpenClaw state dir.

## Launch

Run from the project checkout on EX3:

```bash
sbatch cluster.sbatch
squeue -u prebenmn
```

The job writes `state/slurm-job.json` in the project workspace and logs under `logs/`.

## Relaunch

Run from the project checkout on EX3:

```bash
git pull
sbatch cluster.sbatch
```

## Change Settings

Most settings live in `.env`.

If you change Slack channel id, allowed user, output repo, or gateway port, rerun setup:

```bash
CLANKENSTEIN_RENDER_CONFIG=1 bash setup-project.sh
```

If Codex auth breaks after regenerating config, rerun:

```bash
bash auth-codex.sh login
```

Slurm resources are set by the `#SBATCH` lines in `cluster.sbatch`. Edit those lines or pass `sbatch` options when launching.
