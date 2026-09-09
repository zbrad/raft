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

# rapids-cmake-sha: pin to a fixed commit instead of letting RAPIDS.cmake
# fall through to RAPIDS_BRANCH ("main", an upstream file -- don't edit
# it, it'll just get overwritten on the next upstream sync anyway).
# RAPIDS.cmake's own precedence rules give an explicit -Drapids-cmake-sha
# priority over the branch, so this is the supported override point, not
# a hack. Without this, two builds done at different times can silently
# resolve different transitive dependency versions (rapids-cmake's own
# pins move on its unpinned main) -- confirmed 2026-09-08: raft and cuvs
# builds a few hours apart disagreed on rapids_logger (0.2.3 vs 0.3.0),
# breaking cuvs's configure (duplicate ALIAS target) since it links
# against raft's published/local install tree either way.
#
# Sibling pin: zbrad/cuvs's tuned/build.sh carries the identical SHA --
# keep both in sync by hand when bumping (grep RAPIDS_CMAKE_PIN_SHA in
# each repo's tuned/build.sh). Update by picking a fresh
# `git ls-remote https://github.com/rapidsai/rapids-cmake.git main`
# HEAD, confirming both repos still configure cleanly against it, then
# updating both files together in the same sitting -- never one without
# the other, that's exactly the drift this exists to prevent.
RAPIDS_CMAKE_PIN_SHA="8fc2d05e4b29a2fb7a355192ce19190fcf24c37f"

LIBRAFT_BUILD_DIR="${PROJECT_ROOT}/cpp/build-${GPU_TUNED_VARIANT}" bash build.sh libraft tests --compile-lib --cache-tool=ccache "--cmake-args=\"-DCMAKE_CUDA_ARCHITECTURES=${GPU_TUNED_CUDA_ARCH} -DRAFT_OUTPUT_NAME=${RAFT_LIB_NAME} -Drapids-cmake-sha=${RAPIDS_CMAKE_PIN_SHA}\""

gpu_tuned_verify_arch "${PROJECT_ROOT}/cpp/build-${GPU_TUNED_VARIANT}/lib${RAFT_LIB_NAME}.so" "${GPU_TUNED_CUDA_ARCH}" || exit 1

# CCCL 3.4.0 is the minimum that includes the warpspeed-scan fixes needed
# to avoid a real memory-corruption bug on Blackwell/SM_12x -- see
# gpu_tuned_verify_cccl_version's own comment in tuned/common.sh for the
# full story (this repo's own NVIDIA/raft#3141, closed once verified
# unnecessary against current CCCL). A hard gate, not informational: an
# old CCCL here means a real, previously-hit corruption bug, not just a
# version mismatch.
gpu_tuned_verify_cccl_version "${PROJECT_ROOT}/cpp/build-${GPU_TUNED_VARIANT}/_deps/cccl-src" "3.4.0" || exit 1

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
echo "raft-${GPU_TUNED_VARIANT} build: https://github.com/zbrad/raft @ ${GIT_COMMIT}, CUDA ${CUDA_VERSION}, sm_${GPU_TUNED_CUDA_ARCH}, built ${BUILD_TIMESTAMP}, rapids-cmake @ ${RAPIDS_CMAKE_PIN_SHA}" > "${BUILD_INFO_FILE}"
objcopy --add-section .raft_build_info="${BUILD_INFO_FILE}" "${PROJECT_ROOT}/cpp/build-${GPU_TUNED_VARIANT}/lib${RAFT_LIB_NAME}.so"
rm -f "${BUILD_INFO_FILE}"
