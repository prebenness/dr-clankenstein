#!/usr/bin/env bash
#SBATCH --job-name=build-agent-image
#SBATCH --partition=gh200q
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --time=00:30:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -euo pipefail

REPO=${SLURM_SUBMIT_DIR:-$(pwd -P)}
BUILD_AGENT_TARGET=${BUILD_AGENT_TARGET:-}

cd "$REPO"
mkdir -p logs

if [[ -z "$BUILD_AGENT_TARGET" ]]; then
    case "$(uname -m)" in
        x86_64|amd64) BUILD_AGENT_TARGET=amd64 ;;
        aarch64|arm64) BUILD_AGENT_TARGET=arm64 ;;
        *) echo "Unsupported build host architecture: $(uname -m)" >&2; exit 2 ;;
    esac
fi

echo "Build job: ${SLURM_JOB_ID:-unknown}"
echo "Partition: ${SLURM_JOB_PARTITION:-unknown}"
echo "Node: ${SLURM_JOB_NODELIST:-unknown}"
echo "Host: $(hostname)"
echo "Host architecture: $(uname -m)"
echo "Target: $BUILD_AGENT_TARGET"

bash multiarch/build-agent-images.sh --only "$BUILD_AGENT_TARGET"
