#!/usr/bin/env bash
set -euo pipefail

D1=${D1:-/home/prebenmn/D1}
REPO=$(pwd -P)
DEF=${DEF:-$REPO/Apptainer.def}
OUT_DIR=${OUT_DIR:-$D1/containers}
ONLY=all

usage() {
    cat <<'EOF'
Usage: build-agent-images.sh [--only amd64|arm64|all]

Run from the dr-clankenstein repo on EX3.
Builds:
  $D1/containers/agent-cuda-amd64.sif
  $D1/containers/agent-cuda-arm64.sif

The target architecture must match the build node architecture because
Apptainer executes the image %post section during the build.
EOF
}

while (($#)); do
    case "$1" in
        --only) ONLY=${2:-}; [[ -n "$ONLY" ]] || { echo "--only requires a value" >&2; exit 2; }; shift 2 ;;
        --only=*) ONLY=${1#*=}; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$ONLY" in
    amd64|arm64|all) ;;
    *) echo "--only must be amd64, arm64, or all" >&2; exit 2 ;;
esac

[[ -f "$DEF" ]] || { echo "Missing Apptainer definition: $DEF" >&2; exit 1; }

if command -v module >/dev/null 2>&1; then
    module use /cm/shared/ex3-modules/latest/modulefiles
    module load apptainer/1.4.5
fi

command -v apptainer >/dev/null 2>&1 || { echo "apptainer is not available on PATH" >&2; exit 1; }
mkdir -p "$OUT_DIR"

host_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo amd64 ;;
        aarch64|arm64) echo arm64 ;;
        *) uname -m ;;
    esac
}

require_host_arch() {
    local target=$1
    local host

    host=$(host_arch)
    if [[ "$host" != "$target" ]]; then
        echo "Cannot build target arch=$target on host arch=$host." >&2
        echo "Apptainer runs %post on the build node, so build this target on a $target node." >&2
        echo "For arm64 on EX3, submit: sbatch --partition=gh200q --export=ALL,BUILD_AGENT_TARGET=arm64 multiarch/build-agent-image.sbatch" >&2
        exit 2
    fi
}

build_one() {
    local arch=$1
    local name=$2
    local out=$OUT_DIR/$name
    local tmp=$OUT_DIR/.$name.$$

    require_host_arch "$arch"
    echo "Building $out for arch=$arch"
    rm -f "$tmp"
    apptainer build --fakeroot --arch "$arch" "$tmp" "$DEF"
    mv -f "$tmp" "$out"
    ls -lh "$out"
    apptainer inspect "$out" | grep -E 'org.label-schema.build-arch|org.opencontainers.image' || true
}

if [[ "$ONLY" == "all" || "$ONLY" == "amd64" ]]; then
    build_one amd64 agent-cuda-amd64.sif
fi

if [[ "$ONLY" == "all" || "$ONLY" == "arm64" ]]; then
    build_one arm64 agent-cuda-arm64.sif
fi
