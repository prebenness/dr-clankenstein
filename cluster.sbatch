#!/usr/bin/env bash
#SBATCH --job-name=experiment
#SBATCH --partition=dgx2q
#SBATCH --gres=gpu:2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=24:00:00
#SBATCH --chdir=/home/prebenmn/D1/workspace/dr-clankenstein
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=prebenmn@simula.no

set -euo pipefail

mkdir -p logs

module use /cm/shared/ex3-modules/latest/modulefiles
module load apptainer/1.4.5

D1=/home/prebenmn/D1
REPO=$D1/workspace/dr-clankenstein

apptainer run \
    --nv \
    --pwd /home/node \
    --env LD_LIBRARY_PATH=/.singularity.d/libs \
    --bind "$HOME/.openclaw:/home/node/.openclaw" \
    --bind "$HOME/.gitconfig:/home/node/.gitconfig:ro" \
    --bind "$D1/agent-workspace:/home/node/.openclaw/workspace" \
    --bind "$REPO/AGENTS.md:/home/node/.openclaw/workspace/AGENTS.md:ro" \
    --bind "$REPO/BOOT.md:/home/node/.openclaw/workspace/BOOT.md:ro" \
    --bind "$REPO/HEARTBEAT.md:/home/node/.openclaw/workspace/HEARTBEAT.md:ro" \
    --bind "$REPO/USER.md:/home/node/.openclaw/workspace/USER.md:ro" \
    --env-file "$REPO/.env" \
    "$D1/containers/agent.sif"
