#!/usr/bin/env bash
set -euo pipefail

D1=${D1:-/home/prebenmn/D1}
OUT_DIR=${OUT_DIR:-$D1/containers/multiarch-probes}
CUDA_IMAGE=${CUDA_IMAGE:-docker://nvidia/cuda:12.4.1-devel-ubuntu22.04}
ROCM_IMAGE=${ROCM_IMAGE:-docker://rocm/dev-ubuntu-22.04:latest}

usage() {
    cat <<'EOF'
Usage: build-probe-images.sh [cuda-amd64|cuda-arm64|rocm|all]

Environment:
  OUT_DIR      SIF output directory
  CUDA_IMAGE   Docker URI for the CUDA devel image
  ROCM_IMAGE   Docker URI for the ROCm dev image
  FORCE=1      Rebuild existing SIFs
EOF
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing command: $1" >&2
        exit 1
    }
}

load_apptainer() {
    if command -v module >/dev/null 2>&1; then
        module use /cm/shared/ex3-modules/latest/modulefiles
        module load apptainer/1.4.5
    fi
}

build_one() {
    local name=$1
    local arch=$2
    local image=$3
    local out=$OUT_DIR/$name.sif

    mkdir -p "$OUT_DIR"
    if [[ -f "$out" && "${FORCE:-0}" != "1" ]]; then
        echo "exists: $out"
        return
    fi

    echo "building: $out from $image ${arch:+arch=$arch}"
    if [[ -n "$arch" ]]; then
        apptainer build --arch "$arch" "$out" "$image"
    else
        apptainer build "$out" "$image"
    fi
}

target=${1:-all}
case "$target" in
    -h|--help) usage; exit 0 ;;
esac

load_apptainer
need_cmd apptainer

case "$target" in
    cuda-amd64) build_one cuda-amd64 amd64 "$CUDA_IMAGE" ;;
    cuda-arm64) build_one cuda-arm64 arm64 "$CUDA_IMAGE" ;;
    rocm) build_one rocm-amd64 amd64 "$ROCM_IMAGE" ;;
    all)
        build_one cuda-amd64 amd64 "$CUDA_IMAGE"
        build_one cuda-arm64 arm64 "$CUDA_IMAGE"
        build_one rocm-amd64 amd64 "$ROCM_IMAGE"
        ;;
    *) usage >&2; exit 2 ;;
esac
