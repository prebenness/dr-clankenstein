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

Create that token on GitHub:

1. Create the output repo, for example `prebenness/PROJECT-runs`.
2. Open GitHub `Settings` -> `Developer settings` -> `Personal access tokens` -> `Fine-grained tokens`.
3. Click `Generate new token`.
4. Set `Resource owner` to `prebenness`.
5. Set `Repository access` to `Only select repositories`, then select `PROJECT-runs`.
6. Under `Repository permissions`, set `Contents` to `Read and write`.
7. Generate the token, copy it, and put it in `.env` as `GITHUB_PAT=...`.

Do not put the token in `RUNS_REPO_URL`.

## Slack App

Use one Slack app per live agent. Do not reuse the same Slack app token for two running agents.

Create the app:

1. Open `https://api.slack.com/apps`.
2. Click `Create New App`.
3. Choose `From an app manifest`.
4. Pick your Slack workspace.
5. Paste the contents of `slack-app-manifest.json`.
6. Click through `Next` -> `Create`.

Copy the app token:

1. In the Slack app page, open `Basic Information`.
2. Under `App-Level Tokens`, click `Generate Token and Scopes`.
3. Add the scope `connections:write`.
4. Generate the token.
5. Put it in `.env` as `SLACK_APP_TOKEN=...`.

Copy the bot token:

1. Open `Install App`.
2. Click `Install to Workspace`.
3. Copy `Bot User OAuth Token`.
4. Put it in `.env` as `SLACK_BOT_TOKEN=...`.

Create or choose the project channel:

1. Invite the Slack app to the channel.
2. Right-click the channel in Slack and copy the channel link.
3. The channel id is the final `C...` part of the link.
4. Put it in `.env` as `SLACK_CHANNEL_ID=...`.

OpenClaw Slack docs: `https://docs.openclaw.ai/channels/slack`.

## Setup And Auth

Run once per project from the project checkout on EX3:

```bash
bash setup-project.sh
bash auth-codex.sh login
bash auth-codex.sh list
```

`setup-project.sh` creates the workspace, OpenClaw state dir, rendered OpenClaw config, git helper, and `state/instance.json`.

The rendered OpenClaw config sets the default model to `openai/gpt-5.5`, `xhigh` thinking, and fast mode.

`auth-codex.sh login` starts the manual Codex auth flow, stores auth in the project OpenClaw state dir, and runs OpenClaw with `--set-default`. It can look idle while Apptainer and OpenClaw start; wait for the login prompt.

`auth-codex.sh list` checks that the Codex auth profile is visible in the same project OpenClaw state dir.

On a fresh generated config, OpenClaw may print `Config write anomaly ... missing-meta-before-write`. That means OpenClaw is adding its config metadata and writing a backup; it is not an auth failure.

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
