#!/bin/bash
# raft_env_gb10.sh — detect CUDA installation and export common env vars.
# Source this file; do not execute it directly.
#
# Exported variables:
#   CUDA_HOME      — root of the active CUDA toolkit (e.g. /usr/local/cuda-13.2)
#   CUDA_VERSION   — full dotted version   (e.g. 13.2)
#   CUDA_VERSION_COMPACT — digits only     (e.g. 132)

# 1. Honour an explicit caller-supplied CUDA_HOME.
if [[ -z "${CUDA_HOME:-}" ]]; then
    # 2. Derive from nvcc on PATH.
    if command -v nvcc &>/dev/null; then
        CUDA_HOME="$(nvcc --version 2>/dev/null \
            | sed -n 's|.*Build cuda_\([0-9][0-9]*\.[0-9][0-9]*\)\..*|\1|p' \
            | xargs -I{} readlink -f /usr/local/cuda-{} 2>/dev/null || true)"
    fi
    # 3. Fall back to the /usr/local/cuda symlink.
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

# Surface every installed toolkit, and warn (don't fail) if the one we
# auto-detected isn't the only one present -- this silently bit us once
# already: an earlier build picked up CUDA 13.2 by default while 13.3 was
# also installed, and the mismatch wasn't caught until a much later stage.
mapfile -t _ALL_CUDA_TOOLKITS < <(compgen -G "/usr/local/cuda-*" | sort -V)
if (( ${#_ALL_CUDA_TOOLKITS[@]} > 1 )); then
    echo "WARNING: multiple CUDA toolkits installed: ${_ALL_CUDA_TOOLKITS[*]}"
    echo "         using CUDA_HOME=${CUDA_HOME} -- set CUDA_HOME explicitly if this isn't the one you want."
fi
unset _ALL_CUDA_TOOLKITS
