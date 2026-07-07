#!/bin/bash
# raft_env_rtx50xx.sh — detect CUDA installation and export common env vars.
# Source this file; do not execute it directly.
#
# Exported variables:
#   CUDA_HOME       — root of the active CUDA toolkit (e.g. /usr/local/cuda-13.3)
#   CUDA_VERSION    — full dotted version   (e.g. 13.3)
#   CUDA_VERSION_COMPACT — digits only      (e.g. 133)
#   RTX50_CUDA_ARCH — the one true CUDA arch string for RTX 50xx builds: "120"
#
# ── Rule: RTX 50xx must target bare sm_120, not a family-specific "a" variant
# RTX 50xx (Blackwell consumer) is consumer silicon -- there is no
# family-specific ("accelerated") ISA extension exposed on it, unlike
# datacenter-class chips (e.g. GB10 needs sm_121a -- see
# gb10/raft_env_gb10.sh). "120" covers the whole 50-series
# (5060/5070/5080/5090 all share sm_120) since none of those SKUs differ in
# compute capability -- only in core/memory counts. Every rtx50xx/* script
# must derive its CUDA arch from RTX50_CUDA_ARCH rather than hardcoding
# "120" so this can't drift.
RTX50_CUDA_ARCH="120"
export RTX50_CUDA_ARCH

# verify_rtx50xx_arch <path-to-.so> — assert a compiled library's embedded
# cubins are exactly sm_120 (via cuobjdump), catching a build silently
# produced against the wrong CMAKE_CUDA_ARCHITECTURES.
verify_rtx50xx_arch() {
    local so_file="$1"
    if [[ ! -f "${so_file}" ]]; then
        echo "ERROR: verify_rtx50xx_arch: no such file: ${so_file}" >&2
        return 1
    fi
    local found
    found="$(cuobjdump --list-elf "${so_file}" 2>/dev/null | grep -oE 'sm_[0-9]+a?' | sort -u)"
    if [[ "${found}" != "sm_${RTX50_CUDA_ARCH}" ]]; then
        echo "ERROR: ${so_file} is not built for sm_${RTX50_CUDA_ARCH} (found: ${found:-none})" >&2
        return 1
    fi
    echo "Verified: ${so_file} is built for sm_${RTX50_CUDA_ARCH}"
}
#
# Detection order (same as gb10/raft_env_gb10.sh):
#   1. An explicit caller-supplied CUDA_HOME is always honoured as-is.
#   2. Otherwise, every /usr/local/cuda-X.Y toolkit with a working bin/nvcc
#      is enumerated and the highest version (by `sort -V`) is used.
#   3. If no /usr/local/cuda-X.Y toolkits are found at all, fall back to
#      nvcc on PATH, then the /usr/local/cuda symlink.
#
# NOTE: untested — run on an x86_64 host with RTX 50xx + CUDA installed.

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
