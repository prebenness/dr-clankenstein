#!/usr/bin/env bash
set -euo pipefail

backend=${1:?}
out=/probe-output
work=/tmp/gpu-probe-$backend

rm -rf "$work"
mkdir -p "$work" "$out"

{
    date -u +"container_started_at=%Y-%m-%dT%H:%M:%SZ"
    printf 'backend=%s\n' "$backend"
    uname -a
    id || true
    env | sort
} > "$out/container.txt" 2>&1

case "$backend" in
    cuda)
        export PATH=/usr/local/cuda/bin:$PATH
        export LD_LIBRARY_PATH=/.singularity.d/libs:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}
        nvidia-smi > "$out/gpu-smi.txt" 2>&1 || true
        nvcc --version > "$out/compiler.txt" 2>&1
        nvcc \
            -O2 \
            -std=c++17 \
            -gencode arch=compute_70,code=sm_70 \
            -gencode arch=compute_80,code=sm_80 \
            -gencode arch=compute_86,code=sm_86 \
            -gencode arch=compute_90,code=sm_90 \
            -gencode arch=compute_90,code=compute_90 \
            /probe/cuda_matmul.cu \
            -o "$work/cuda_probe" > "$out/build.log" 2>&1
        "$work/cuda_probe" > "$out/result.json"
        ;;
    hip)
        export PATH=/opt/rocm/bin:$PATH
        export LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib64:${LD_LIBRARY_PATH:-}
        rocm-smi > "$out/gpu-smi.txt" 2>&1 || true
        hipcc --version > "$out/compiler.txt" 2>&1
        hipcc \
            -O2 \
            -std=c++17 \
            /probe/hip_matmul.cpp \
            -o "$work/hip_probe" > "$out/build.log" 2>&1
        "$work/hip_probe" > "$out/result.json"
        ;;
    *)
        echo "Unknown backend: $backend" >&2
        exit 2
        ;;
esac

cat "$out/result.json"
