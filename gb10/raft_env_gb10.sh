#!/bin/bash
# raft_env_gb10.sh — detect CUDA installation and export common env vars.
# Source this file; do not execute it directly.
#
# Exported variables:
#   CUDA_HOME      — root of the active CUDA toolkit (e.g. /usr/local/cuda-13.3)
#   CUDA_VERSION   — full dotted version   (e.g. 13.3)
#   CUDA_VERSION_COMPACT — digits only     (e.g. 133)
#   GB10_CUDA_ARCH — the one true CUDA arch string for GB10 builds: "121a"
#
# ── Rule: GB10 must target sm_121a, not bare sm_121 ─────────────────────────
# The trailing "a" selects the Blackwell family-specific ("accelerated") ISA
# extensions -- e.g. the newer tensor-core instructions -- that are exposed on
# datacenter-class Blackwell silicon but are absent from the generic sm_121
# target. GB10 (Grace Blackwell, DGX Spark) is datacenter-class, so it needs
# the "a" variant. This is the opposite of RTX 50xx (consumer Blackwell),
# which must use bare sm_120 (no "a") -- see wsl/raft_cupy_build_rtx50xx.sh.
# Every gb10/* script must derive its CUDA arch from GB10_CUDA_ARCH rather
# than hardcoding "121a"/"121" so this can't drift again.
GB10_CUDA_ARCH="121a"
export GB10_CUDA_ARCH

# verify_gb10_arch <path-to-.so> — assert a compiled library's embedded
# cubins are exactly sm_121a (via cuobjdump), catching a build silently
# produced against the wrong CMAKE_CUDA_ARCHITECTURES (e.g. a stale build
# directory left over from an RTX 50xx / bare-121 build).
verify_gb10_arch() {
    local so_file="$1"
    if [[ ! -f "${so_file}" ]]; then
        echo "ERROR: verify_gb10_arch: no such file: ${so_file}" >&2
        return 1
    fi
    local found
    found="$(cuobjdump --list-elf "${so_file}" 2>/dev/null | grep -oE 'sm_[0-9]+a?' | sort -u)"
    if [[ "${found}" != "sm_${GB10_CUDA_ARCH}" ]]; then
        echo "ERROR: ${so_file} is not built for sm_${GB10_CUDA_ARCH} (found: ${found:-none})" >&2
        return 1
    fi
    echo "Verified: ${so_file} is built for sm_${GB10_CUDA_ARCH}"
}
#
# Detection order:
#   1. An explicit caller-supplied CUDA_HOME is always honoured as-is.
#   2. Otherwise, every /usr/local/cuda-X.Y toolkit with a working bin/nvcc
#      is enumerated and the highest version (by `sort -V`) is used. This
#      machine has 13.0/13.1/13.2/13.3 installed side by side, and relying
#      on nvcc-on-PATH or the /usr/local/cuda symlink silently picked the
#      wrong one once before -- the mismatch wasn't caught until a much
#      later build stage.
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
