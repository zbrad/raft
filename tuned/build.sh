#!/bin/bash
# build.sh <variant> — build libraft + tests for the given GPU
# variant (gb10/rtx40/rtx50). Shared implementation behind every
# gb10/rtx40/rtx50 raft_build_<variant>.sh wrapper.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GPU_TUNED_ARG_VARIANT="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1
cd "${PROJECT_ROOT}"

# raft-<variant>-<cuda_tag>, matching zbrad/cuvs's libcuvs-<variant>-<tag>.so
# naming (tuned/build.sh's CUVS_LIB_NAME there) -- see cpp/CMakeLists.txt's
# RAFT_OUTPUT_NAME override, and tuned/wheel.sh, which shares this build
# dir/CMakeCache and has been updated to expect this name too (not the bare
# "libraft.so" it used to look for).
RAFT_LIB_NAME="raft-${GPU_TUNED_VARIANT}-${CUDA_TAG}"

LIBRAFT_BUILD_DIR="${PROJECT_ROOT}/cpp/build-${GPU_TUNED_VARIANT}" bash build.sh libraft tests --compile-lib --cache-tool=ccache "--cmake-args=\"-DCMAKE_CUDA_ARCHITECTURES=${GPU_TUNED_CUDA_ARCH} -DRAFT_OUTPUT_NAME=${RAFT_LIB_NAME}\""

gpu_tuned_verify_arch "${PROJECT_ROOT}/cpp/build-${GPU_TUNED_VARIANT}/lib${RAFT_LIB_NAME}.so" "${GPU_TUNED_CUDA_ARCH}" || exit 1

# Embed a build-info string into a custom ELF section on the variant-
# qualified copy (readable later via `readelf -p .raft_build_info <lib>`
# or plain `strings`), so which CUDA 13.x *minor* toolkit (and which repo
# fork/commit) built this specific .so is recoverable even if the file
# gets copied/renamed away from its wheel/VERSION metadata. Full ISO-8601
# UTC timestamp, not just a date -- see CLAUDE.md's memory-timestamp
# convention for why bare dates aren't enough (multiple builds can land
# the same day).
BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
GIT_COMMIT="$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
BUILD_INFO_FILE="$(mktemp)"
echo "raft-${GPU_TUNED_VARIANT} build: https://github.com/zbrad/raft @ ${GIT_COMMIT}, CUDA ${CUDA_VERSION}, sm_${GPU_TUNED_CUDA_ARCH}, built ${BUILD_TIMESTAMP}" > "${BUILD_INFO_FILE}"
objcopy --add-section .raft_build_info="${BUILD_INFO_FILE}" "${PROJECT_ROOT}/cpp/build-${GPU_TUNED_VARIANT}/lib${RAFT_LIB_NAME}.so"
rm -f "${BUILD_INFO_FILE}"
