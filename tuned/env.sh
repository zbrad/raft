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
#   CUDA_VER / CUDA_TAG   — the toolkit id (13.3 / cu133), as in the other tuned repos
#   GPU_TUNED_VARIANT/GPU_TUNED_PLATFORM/GPU_TUNED_CUDA_ARCH/GPU_TUNED_HW_LABEL
#                          — from the shared tuned/common-data/devices/<variant>.conf
#   RAFT_DEVICE_LABEL     — from tuned/repo.env
#
# The toolkit comes from the vendored definitions in tuned/common-data/toolkits/<id>.env
# (zbrad/tuned-common), never from /usr/local/cuda or from what is installed. There is no
# default: name it with CUDA_TAG=cu133 or CUDA_VER=13.3. With neither set the loader fails and
# lists the defined toolkits (at a terminal it asks which to use, for that run only).
#
# Also defines gpu_tuned_verify_arch() -- see below.

GPU_TUNED_ARG_VARIANT="$1"
if [[ -z "${GPU_TUNED_ARG_VARIANT}" ]]; then
    echo "ERROR: env.sh requires a variant argument (gb10/rtx40/rtx50)" >&2
    return 1 2>/dev/null || exit 1
fi

GPU_TUNED_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU_TUNED_DATA_DIR="${GPU_TUNED_SELF_DIR}/common-data"
# shellcheck source=common-data/devices/gb10.conf
source "${GPU_TUNED_DATA_DIR}/devices/${GPU_TUNED_ARG_VARIANT}.conf" || return 1 2>/dev/null || exit 1
export GPU_TUNED_VARIANT GPU_TUNED_PLATFORM GPU_TUNED_CUDA_ARCH GPU_TUNED_HW_LABEL

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

# --- CUDA toolkit: chosen from tuned/common-data/toolkits, never inferred. CUDA_TAG (cu133) or
#     CUDA_VER (13.3) select one; neither set is an error listing the defined ones. Exports
#     CUDA_VER, CUDA_TAG, CUDA_HOME and puts $CUDA_HOME/bin on PATH. ---
_raft_tk="${CUDA_TAG:-}"
_raft_req_ver="${CUDA_VER:-}"
if [ -z "${_raft_tk}" ] && [ -n "${_raft_req_ver}" ]; then
    _raft_tk="cu${_raft_req_ver//./}"                           # 13.3 -> cu133
fi
gpu_tuned_load_toolkit "${GPU_TUNED_DATA_DIR}" "${GPU_TUNED_VARIANT}" "${_raft_tk}" || return 1 2>/dev/null || exit 1
if [ -n "${_raft_req_ver}" ] && [ "${_raft_req_ver}" != "${TOOLKIT_CUDA_VER}" ]; then
    echo "[tuned/env] ERROR: CUDA_VER=${_raft_req_ver} conflicts with toolkit ${CUDA_TAG} (CUDA ${TOOLKIT_CUDA_VER})." >&2
    return 1 2>/dev/null || exit 1
fi
unset _raft_tk _raft_req_ver
gpu_tuned_verify_toolkit || return 1 2>/dev/null || exit 1

# raft's own names for the toolkit version, used throughout tuned/ and the wheel scripts.
CUDA_VERSION="${CUDA_VER}"
CUDA_VERSION_COMPACT="${CUDA_VER//./}"
export CUDA_VERSION CUDA_VERSION_COMPACT

# --- Repo-specific settings (the device label), loaded last; may not change any shared
#     device/toolkit key. ---
gpu_tuned_load_repo_env "${GPU_TUNED_SELF_DIR}/repo.env" || return 1 2>/dev/null || exit 1
export RAFT_DEVICE_LABEL

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

echo "CUDA_HOME=${CUDA_HOME}  CUDA_VERSION=${CUDA_VERSION}  CUDA_VERSION_COMPACT=${CUDA_VERSION_COMPACT}"
