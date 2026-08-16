# dr-clankenstein

OpenClaw research-agent harness for EX3 Slurm jobs.

Use one isolated instance per research project:

- one Slack app and channel;
- one GitHub output repo;
- one `.env`;
- one workspace dir;
- one OpenClaw state dir;
- one source checkout;
- one gateway port.

Do not share Slack app tokens, workspace dirs, OpenClaw state dirs, or gateway ports between live agents.

## New Project Setup

A new project is mostly `.env` work. First create the checkout, then collect the values in sections 2-4, then edit `.env` once in section 5.

### 1. Create the checkout

EX3, cwd: `~/D1/workspace`:

```bash
cd ~/D1/workspace
git clone git@github.com:prebenness/dr-clankenstein.git dr-clankenstein-PROJECT
cd dr-clankenstein-PROJECT
cp .env.example .env
cp cluster.sbatch.example cluster.sbatch
chmod 600 .env
```

Use `PROJECT` as a short id, for example `bnn-timeseries`.

`cluster.sbatch` is local and ignored. Edit its `#SBATCH` lines only if this project needs different Slurm resources.

### 2. Choose local values

You need these project-unique `.env` entries:

```text
CLANKENSTEIN_ID=PROJECT
CLANKENSTEIN_WORKSPACE_DIR=/home/prebenmn/D1/agent-workspaces/PROJECT
CLANKENSTEIN_OPENCLAW_DIR=/home/prebenmn/D1/openclaw-state/PROJECT
CLANKENSTEIN_GATEWAY_PORT=18790
OPENCLAW_GATEWAY_TOKEN=<random hex>
```

EX3, cwd: project checkout:

```bash
openssl rand -hex 32
```

Use a unique gateway port if two live projects may land on the same node. Leave image settings at their defaults unless setup reports a missing image.

### 3. Create the Slack app and channel

1. Open `https://api.slack.com/apps`.
2. Click `Create New App`.
3. Choose `From an app manifest`.
4. Pick the Slack workspace.
5. Paste the contents of `slack-app-manifest.json`.
6. Click through `Next` -> `Create`.

Create the app token:

1. Open `Basic Information`.
2. Under `App-Level Tokens`, click `Generate Token and Scopes`.
3. Add the scope `connections:write`.
4. Generate the token.

Create the bot token:

1. Open `Install App`.
2. Click `Install to Workspace`.
3. Copy `Bot User OAuth Token`.

Create or choose the project channel:

1. Invite the Slack app to the channel.
2. Right-click the channel in Slack and copy the channel link.
3. The channel id is the final `C...` part of the link.

You need these `.env` entries:

```text
SLACK_APP_TOKEN=xapp-...
SLACK_BOT_TOKEN=xoxb-...
SLACK_CHANNEL_ID=C...
SLACK_CHANNEL_NAME=dr-clankenstein-PROJECT
```

### 4. Create the output repo and GitHub token

You need these `.env` entries:

```text
RUNS_REPO_URL=https://github.com/prebenness/PROJECT-runs.git
GITHUB_PAT=github_pat_...
```

`GITHUB_PAT` must have contents read/write access to that output repo.

Create the token on GitHub:

1. Create the output repo, for example `prebenness/PROJECT-runs`.
2. Open GitHub `Settings` -> `Developer settings` -> `Personal access tokens` -> `Fine-grained tokens`.
3. Click `Generate new token`.
4. Set `Resource owner` to `prebenness`.
5. Set `Repository access` to `Only select repositories`, then select `PROJECT-runs`.
6. Under `Repository permissions`, set `Contents` to `Read and write`.
7. Generate and copy the token.

Do not put the token in `RUNS_REPO_URL`.

### 5. Edit `.env`, then run setup and auth

Now fill `.env` with the values from sections 2-4.

EX3, cwd: project checkout:

```bash
nano .env
bash setup-project.sh
bash auth-codex.sh login
bash auth-codex.sh list
bash auth-codex.sh probe
```

`setup-project.sh` creates the workspace, OpenClaw state dir, rendered config, git helper, `state/instance.json`, and plugin registry.

`auth-codex.sh login` starts the ChatGPT device-code login used by the Codex runtime.

`auth-codex.sh list` checks the auth profile in this project's OpenClaw state dir.

`auth-codex.sh probe` checks that OpenClaw can reach the configured OpenAI model route with that profile.

A fresh config may print `Config write anomaly ... missing-meta-before-write`; OpenClaw is writing metadata, not failing auth.

### 6. Launch

EX3, cwd: project checkout:

```bash
sbatch cluster.sbatch
squeue -u prebenmn
```

The job writes `state/slurm-job.json` in the project workspace and logs under `logs/`.

## Relaunch

EX3, cwd: project checkout:

```bash
git pull
sbatch cluster.sbatch
```

## Change Settings

If you change Slack channel id, allowed user, output repo, or gateway port, rerun setup:

EX3, cwd: project checkout:

```bash
CLANKENSTEIN_RENDER_CONFIG=1 bash setup-project.sh
```

If Codex auth breaks after regenerating config, rerun:

EX3, cwd: project checkout:

```bash
bash auth-codex.sh login
```

Slurm resources are set by the `#SBATCH` lines in the ignored local `cluster.sbatch`. `cluster.sbatch.example` is the tracked template.

## Build Images

Only needed when the container definition or OpenClaw version changes.

EX3 amd64 node, cwd: project checkout:

```bash
bash multiarch/build-agent-images.sh --only amd64
```

EX3 arm64 Slurm build, cwd: project checkout:

```bash
sbatch --partition=gh200q --export=ALL,BUILD_AGENT_TARGET=arm64 multiarch/build-agent-image.sbatch
```
