#!/bin/bash
# env.sh <variant> — detect CUDA installation and export common
# env vars for a given GPU variant (gb10/rtx40/rtx50). Source this
# file with the variant as $1; do not execute it directly.
#
# This is the shared implementation behind every gb10/rtx40/rtx50
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
    echo "ERROR: env.sh requires a variant argument (gb10/rtx40/rtx50)" >&2
    return 1 2>/dev/null || exit 1
fi

GPU_TUNED_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=devices/rtx50.conf
source "${GPU_TUNED_SELF_DIR}/devices/${GPU_TUNED_ARG_VARIANT}.conf" || return 1 2>/dev/null || exit 1
export GPU_TUNED_VARIANT GPU_TUNED_PLATFORM GPU_TUNED_CUDA_ARCH GPU_TUNED_HW_LABEL GPU_TUNED_DEVICE_LABEL

# shellcheck source=common.sh
# Vendored from https://github.com/zbrad/tuned-common (pinned commit --
# see common.sh's own header/sync instructions to update). Provides
# gpu_tuned_verify_arch/verify_cuda_compat/assert_platform, shared
# verbatim across the fleet instead of hand-copied-and-edited per repo.
# NOT used for embed_build_info here: raft deliberately stamps every
# package (libraft, librmm, ...) into the SAME .raft_build_info section
# rather than one section per package (see raft_wheel_common.sh's own
# embed_build_info -- validate_wheels depends on that section name being
# constant), which doesn't fit the shared function's one-section-per-
# package design -- kept as its own local definition on purpose.
source "${GPU_TUNED_SELF_DIR}/common.sh" || return 1 2>/dev/null || exit 1

# Fail loudly if this script is run on the wrong host, rather than letting
# a mismatched build silently produce wrong-architecture binaries that
# only surface as a confusing failure several steps later (gpu_tuned_verify_arch
# below catches the compiled-.so case; this catches it even earlier, before
# any compilation happens at all).
gpu_tuned_assert_platform "${GPU_TUNED_PLATFORM}" "${GPU_TUNED_VARIANT}" || return 1 2>/dev/null || exit 1

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
# "cu133" form, matching zbrad/cuvs's tuned/env.sh CUDA_TAG convention --
# used to name this build's own output (see tuned/build.sh's
# RAFT_LIB_NAME) the same way cuvs names its libcuvs-<variant>-<tag>.so.
CUDA_TAG="${CUDA_TAG:-cu${CUDA_VERSION_COMPACT}}"

export CUDA_HOME CUDA_VERSION CUDA_VERSION_COMPACT CUDA_TAG

# --- Output layout: one tree per toolkit, tuned/build/<cuda-tag>/ (gitignored via build/), with no
#     variant level: cmake/ (the one fixed compile path), dist/, dist-shared/, releases/ (generated
#     checksums and test logs; the tracked RELEASE_NOTES_*.md stay in tuned/releases/), ccache/,
#     timing.tsv. gpu_tuned_out_dir (common.sh) names these; the claim refuses a tree last used by
#     another variant. ---
GPU_TUNED_REPO_ROOT="$(cd "${GPU_TUNED_SELF_DIR}/.." && pwd)"
gpu_tuned_claim_toolkit_tree "${GPU_TUNED_REPO_ROOT}" "${CUDA_TAG}" "${GPU_TUNED_VARIANT}" || return 1 2>/dev/null || exit 1
GPU_TUNED_BUILD_ROOT="${GPU_TUNED_REPO_ROOT}/tuned/build/${CUDA_TAG}"
# ccache per toolkit (upstream's build.sh --cache-tool=ccache passes it to CMake as the compiler
# launcher). CCACHE_DIR also makes ccache ignore ~/.config/ccache/ccache.conf, so its small default
# size cap would apply: set it here (a RAPIDS build is far larger than 5 GB).
export CCACHE_DIR="${GPU_TUNED_BUILD_ROOT}/ccache"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-40G}"
export GPU_TUNED_BUILD_ROOT

# gpu_tuned_assert_cmake_cache_consistent <cmake-build-dir>: fail if an existing CMake cache was
# configured for another toolkit or another source tree (it would silently keep them).
gpu_tuned_assert_cmake_cache_consistent() {
    local cache="${1}/CMakeCache.txt" cached
    [[ -f "${cache}" ]] || return 0
    cached="$(sed -n 's/^CMAKE_CUDA_COMPILER:FILEPATH=//p' "${cache}" | head -1)"
    if [[ -n "${cached}" && "${cached}" != "${CUDA_HOME}/bin/nvcc" ]]; then
        echo "ERROR: ${cache} was configured with ${cached}, but CUDA_HOME=${CUDA_HOME}. Remove that tree first: rm -rf ${1}" >&2
        return 1
    fi
    cached="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "${cache}" | head -1)"
    if [[ -n "${cached}" && "${cached}" != "${GPU_TUNED_REPO_ROOT}/cpp" ]]; then
        echo "ERROR: ${cache} was configured for source tree ${cached}, not ${GPU_TUNED_REPO_ROOT}/cpp -- looks copied from another checkout. Remove that tree first: rm -rf ${1}" >&2
        return 1
    fi
}

# Prepend CUDA bin to PATH if not already present.
case ":${PATH}:" in
    *":${CUDA_HOME}/bin:"*) ;;
    *) export PATH="${CUDA_HOME}/bin:${PATH}" ;;
esac

echo "CUDA_HOME=${CUDA_HOME}  CUDA_VERSION=${CUDA_VERSION}  CUDA_VERSION_COMPACT=${CUDA_VERSION_COMPACT}"
