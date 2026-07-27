#!/bin/bash
# env.sh <variant> — detect CUDA installation and export common
# env vars for a given GPU variant (gb10/rtx40xx/rtx50xx). Source this
# file with the variant as $1; do not execute it directly.
#
# This is the shared implementation behind every gb10/rtx40xx/rtx50xx
# raft_env_<variant>.sh wrapper (each just does
# `source tuned/env.sh <variant>`). Formerly three
# byte-identical copies of this detection logic with only variable names
# substituted -- see the gpu_tuned refactor plan for the full duplication
# analysis.
#
# Exported variables:
#   CUDA_HOME             — root of the active CUDA toolkit (e.g. /usr/local/cuda-13.3)
#   CUDA_VERSION          — full dotted version   (e.g. 13.3)
#   CUDA_VERSION_COMPACT  — digits only            (e.g. 133)
#   GPU_TUNED_VARIANT/GPU_TUNED_PLATFORM/GPU_TUNED_CUDA_ARCH/GPU_TUNED_HW_LABEL/GPU_TUNED_DEVICE_LABEL
#                          — from tuned/devices/<variant>.conf, re-exported here for convenience
#
# Also defines gpu_tuned_verify_arch() -- see below.

GPU_TUNED_ARG_VARIANT="$1"
if [[ -z "${GPU_TUNED_ARG_VARIANT}" ]]; then
    echo "ERROR: env.sh requires a variant argument (gb10/rtx40xx/rtx50xx)" >&2
    return 1 2>/dev/null || exit 1
fi

GPU_TUNED_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=devices/rtx50xx.conf
source "${GPU_TUNED_SELF_DIR}/devices/${GPU_TUNED_ARG_VARIANT}.conf" || return 1 2>/dev/null || exit 1
export GPU_TUNED_VARIANT GPU_TUNED_PLATFORM GPU_TUNED_CUDA_ARCH GPU_TUNED_HW_LABEL GPU_TUNED_DEVICE_LABEL

# Fail loudly if this script is run on the wrong host, rather than letting
# a mismatched build silently produce wrong-architecture binaries that
# only surface as a confusing failure several steps later (gpu_tuned_verify_arch
# below catches the compiled-.so case; this catches it even earlier, before
# any compilation happens at all).
if [[ "$(uname -m)" != "${GPU_TUNED_PLATFORM}" ]]; then
    echo "ERROR: env.sh: expected platform '${GPU_TUNED_PLATFORM}' for" \
         "variant '${GPU_TUNED_VARIANT}', but uname -m reports '$(uname -m)'." >&2
    return 1 2>/dev/null || exit 1
fi

# gpu_tuned_verify_arch <path-to-.so> — assert a compiled library's
# embedded cubins are exactly sm_${GPU_TUNED_CUDA_ARCH} (via cuobjdump),
# catching a build silently produced against the wrong
# CMAKE_CUDA_ARCHITECTURES (e.g. a stale build directory left over from a
# different variant's build).
gpu_tuned_verify_arch() {
    local so_file="$1"
    if [[ ! -f "${so_file}" ]]; then
        echo "ERROR: gpu_tuned_verify_arch: no such file: ${so_file}" >&2
        return 1
    fi
    local found
    found="$(cuobjdump --list-elf "${so_file}" 2>/dev/null | grep -oE 'sm_[0-9]+a?' | sort -u)"
    if [[ "${found}" != "sm_${GPU_TUNED_CUDA_ARCH}" ]]; then
        echo "ERROR: ${so_file} is not built for sm_${GPU_TUNED_CUDA_ARCH} (found: ${found:-none})" >&2
        return 1
    fi
    echo "Verified: ${so_file} is built for sm_${GPU_TUNED_CUDA_ARCH}"
}

# Detection order:
#   1. An explicit caller-supplied CUDA_HOME is always honoured as-is.
#   2. Otherwise, every /usr/local/cuda-X.Y toolkit with a working bin/nvcc
#      is enumerated and the highest version (by `sort -V`) is used. This
#      matters on hosts with several toolkits installed side by side (e.g.
#      13.0/13.1/13.2/13.3) -- relying on nvcc-on-PATH or the
#      /usr/local/cuda symlink silently picked the wrong one once during
#      gb10 development, and the mismatch wasn't caught until a much later
#      build stage.
#   3. If no /usr/local/cuda-X.Y toolkits are found at all, fall back to
#      nvcc on PATH, then the /usr/local/cuda symlink.

if [[ -z "${CUDA_HOME:-}" ]]; then
    mapfile -t _CUDA_TOOLKITS < <(
        for d in /usr/local/cuda-*; do
            [[ -x "${d}/bin/nvcc" ]] && echo "${d}"
        done | sort -V
    )
    if (( ${#_CUDA_TOOLKITS[@]} > 0 )); then
        CUDA_HOME="$(readlink -f "${_CUDA_TOOLKITS[-1]}")"
        if (( ${#_CUDA_TOOLKITS[@]} > 1 )); then
            echo "NOTE: multiple CUDA toolkits installed: ${_CUDA_TOOLKITS[*]}"
            echo "      defaulting to the most recent: ${CUDA_HOME} -- set CUDA_HOME explicitly to override."
        fi
    fi
    unset _CUDA_TOOLKITS
fi

if [[ -z "${CUDA_HOME:-}" ]]; then
    if command -v nvcc &>/dev/null; then
        CUDA_HOME="$(nvcc --version 2>/dev/null \
            | sed -n 's|.*Build cuda_\([0-9][0-9]*\.[0-9][0-9]*\)\..*|\1|p' \
            | xargs -I{} readlink -f /usr/local/cuda-{} 2>/dev/null || true)"
    fi
    if [[ -z "${CUDA_HOME:-}" && -e /usr/local/cuda ]]; then
        CUDA_HOME="$(readlink -f /usr/local/cuda)"
    fi
fi

if [[ -z "${CUDA_HOME:-}" ]]; then
    echo "ERROR: could not locate CUDA toolkit. Set CUDA_HOME and re-run." >&2
    return 1 2>/dev/null || exit 1
fi

if [[ ! -x "${CUDA_HOME}/bin/nvcc" ]]; then
    echo "ERROR: nvcc not found under CUDA_HOME=${CUDA_HOME}" >&2
    return 1 2>/dev/null || exit 1
fi

# Parse version from nvcc inside the detected CUDA_HOME.
CUDA_VERSION="$("${CUDA_HOME}/bin/nvcc" --version \
    | sed -n 's/.*release \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')"
CUDA_VERSION_COMPACT="${CUDA_VERSION//./}"

export CUDA_HOME CUDA_VERSION CUDA_VERSION_COMPACT

# Prepend CUDA bin to PATH if not already present.
case ":${PATH}:" in
    *":${CUDA_HOME}/bin:"*) ;;
    *) export PATH="${CUDA_HOME}/bin:${PATH}" ;;
esac

echo "CUDA_HOME=${CUDA_HOME}  CUDA_VERSION=${CUDA_VERSION}  CUDA_VERSION_COMPACT=${CUDA_VERSION_COMPACT}"
