#!/usr/bin/env bash
set -euo pipefail

backend=${1:?}
out=/probe-output
work=/tmp/gpu-probe-$backend

rm -rf "$work"
mkdir -p "$work" "$out"

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_failure_result() {
    local detail=$1
    {
        printf '{"ok":false,"backend":'
        printf '"%s"' "$(json_escape "$backend")"
        printf ',"error":'
        printf '"%s"' "$(json_escape "$detail")"
        printf ',"node":'
        printf '"%s"' "$(json_escape "${SLURMD_NODENAME:-}")"
        printf ',"partition":'
        printf '"%s"' "$(json_escape "${SLURM_JOB_PARTITION:-}")"
        printf ',"job_id":'
        printf '"%s"' "$(json_escape "${SLURM_JOB_ID:-}")"
        printf '}\n'
    } > "$out/result.json"
}

access_report() {
    local path
    for path in "$@"; do
        [[ -e "$path" ]] || continue
        printf '%s read=%s write=%s\n' "$path" \
            "$([[ -r "$path" ]] && echo yes || echo no)" \
            "$([[ -w "$path" ]] && echo yes || echo no)"
    done
}

run_hip_probe_variant() {
    local variant=$1

    case "$variant" in
        primary)
            ;;
        no-visibility)
            unset CUDA_VISIBLE_DEVICES GPU_DEVICE_ORDINAL HIP_VISIBLE_DEVICES ROCR_VISIBLE_DEVICES
            ;;
        hip0)
            unset CUDA_VISIBLE_DEVICES GPU_DEVICE_ORDINAL ROCR_VISIBLE_DEVICES
            export HIP_VISIBLE_DEVICES=0
            ;;
        rocr0)
            unset CUDA_VISIBLE_DEVICES GPU_DEVICE_ORDINAL HIP_VISIBLE_DEVICES
            export ROCR_VISIBLE_DEVICES=0
            ;;
        gpu-ordinal0)
            unset CUDA_VISIBLE_DEVICES HIP_VISIBLE_DEVICES ROCR_VISIBLE_DEVICES
            export GPU_DEVICE_ORDINAL=0
            ;;
        cuda0)
            unset GPU_DEVICE_ORDINAL HIP_VISIBLE_DEVICES ROCR_VISIBLE_DEVICES
            export CUDA_VISIBLE_DEVICES=0
            ;;
        host-libs-first)
            export LD_LIBRARY_PATH=/.singularity.d/libs:/opt/rocm/lib:/opt/rocm/lib64:${LD_LIBRARY_PATH:-}
            ;;
        host-libs-first-no-visibility)
            unset CUDA_VISIBLE_DEVICES GPU_DEVICE_ORDINAL HIP_VISIBLE_DEVICES ROCR_VISIBLE_DEVICES
            export LD_LIBRARY_PATH=/.singularity.d/libs:/opt/rocm/lib:/opt/rocm/lib64:${LD_LIBRARY_PATH:-}
            ;;
        *)
            echo "Unknown HIP variant: $variant" >&2
            return 2
            ;;
    esac

    {
        echo "variant=$variant"
        env | sort
    } > "$out/env-$variant.txt"
    rocminfo > "$out/rocminfo-$variant.txt" 2>&1 || true
    rocm_agent_enumerator > "$out/rocm-agent-enumerator-$variant.txt" 2>&1 || true
    "$work/hip_probe"
}

{
    date -u +"container_started_at=%Y-%m-%dT%H:%M:%SZ"
    printf 'backend=%s\n' "$backend"
    uname -a
    id || true
    groups || true
    umask
    printf 'PROBE_HOST_CUDA_VISIBLE_DEVICES=%s\n' "${PROBE_HOST_CUDA_VISIBLE_DEVICES:-}"
    printf 'PROBE_HOST_GPU_DEVICE_ORDINAL=%s\n' "${PROBE_HOST_GPU_DEVICE_ORDINAL:-}"
    printf 'PROBE_HOST_HIP_VISIBLE_DEVICES=%s\n' "${PROBE_HOST_HIP_VISIBLE_DEVICES:-}"
    printf 'PROBE_HOST_ROCR_VISIBLE_DEVICES=%s\n' "${PROBE_HOST_ROCR_VISIBLE_DEVICES:-}"
    env | sort
} > "$out/container.txt" 2>&1

case "$backend" in
    cuda)
        export PATH=/usr/local/cuda/bin:$PATH
        export LD_LIBRARY_PATH=/.singularity.d/libs:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}
        ls -la /dev/nvidia* > "$out/devices.txt" 2>&1 || true
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
        "$work/cuda_probe" > "$out/result.json" 2> "$out/runtime.err"
        ;;
    hip)
        export PATH=/opt/rocm/bin:$PATH
        export LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib64:${LD_LIBRARY_PATH:-}
        {
            id || true
            groups || true
            ls -la /dev/kfd /dev/dri 2>&1 || true
            printf '\n--- /dev/dri ---\n'
            ls -la /dev/dri/* 2>&1 || true
            printf '\n--- device stats ---\n'
            stat -c '%A %U %G %u:%g %n' /dev/kfd /dev/dri /dev/dri/* 2>&1 || true
            printf '\n--- access checks ---\n'
            access_report /dev/kfd /dev/dri/renderD* /dev/dri/card*
            printf '\n--- sysfs drm ---\n'
            ls -la /sys/class/drm /sys/class/drm/* 2>&1 || true
        } > "$out/devices.txt"
        rocm-smi > "$out/gpu-smi.txt" 2>&1 || true
        rocminfo > "$out/rocminfo.txt" 2>&1 || true
        rocm_agent_enumerator > "$out/rocm-agent-enumerator.txt" 2>&1 || true
        hipconfig > "$out/hipconfig.txt" 2>&1 || true
        hipconfig --full > "$out/hipconfig-full.txt" 2>&1 || true
        {
            command -v hipcc || true
            command -v rocminfo || true
            command -v rocm-smi || true
            command -v rocm_agent_enumerator || true
            command -v strace || true
            printf '\n--- ldconfig ---\n'
            ldconfig -p 2>/dev/null | grep -Ei 'hsa|amdhip|rocm|drm' || true
            printf '\n--- rocm libs ---\n'
            find /opt/rocm -maxdepth 4 -type f \( -name 'libamdhip64.so*' -o -name 'libhsa-runtime64.so*' -o -name 'libdrm*.so*' \) -print 2>/dev/null || true
        } > "$out/runtime-inventory.txt"
        hipcc --version > "$out/compiler.txt" 2>&1
        hipcc \
            -O2 \
            -std=c++17 \
            /probe/hip_matmul.cpp \
            -o "$work/hip_probe" > "$out/build.log" 2>&1
        {
            ldd "$work/hip_probe" || true
        } > "$out/ldd-hip-probe.txt" 2>&1

        variants=(primary no-visibility hip0 rocr0 gpu-ordinal0 cuda0 host-libs-first host-libs-first-no-visibility)
        for variant in "${variants[@]}"; do
            if ( run_hip_probe_variant "$variant" ) > "$out/result-$variant.json" 2> "$out/runtime-$variant.err"; then
                cp "$out/result-$variant.json" "$out/result.json"
                echo "$variant" > "$out/successful-variant.txt"
                break
            fi
        done

        if [[ ! -s "$out/result.json" ]]; then
            write_failure_result "all HIP visibility variants failed"
            exit 1
        fi
        ;;
    *)
        echo "Unknown backend: $backend" >&2
        exit 2
        ;;
esac

cat "$out/result.json"
