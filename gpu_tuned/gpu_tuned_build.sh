#!/bin/bash
# gpu_tuned_build.sh <variant> — build libraft + tests for the given GPU
# variant (gb10/rtx40xx/rtx50xx). Shared implementation behind every
# gb10/rtx40xx/rtx50xx raft_build_<variant>.sh wrapper.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GPU_TUNED_ARG_VARIANT="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=gpu_tuned_env.sh
source "${PROJECT_ROOT}/gpu_tuned/gpu_tuned_env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1
cd "${PROJECT_ROOT}"
LIBRAFT_BUILD_DIR="${PROJECT_ROOT}/cpp/build-${GPU_TUNED_VARIANT}" bash build.sh libraft tests --compile-lib --cache-tool=ccache "--cmake-args=\"-DCMAKE_CUDA_ARCHITECTURES=${GPU_TUNED_CUDA_ARCH}\""

# Copy (not rename) alongside the bare libraft.so: gpu_tuned_wheel.sh's
# later `cmake --install` still needs the original bare-named file at this
# exact path (baked into cmake_install.cmake at configure time). The
# variant-qualified copy exists purely so this build's own artifact can't
# get confused with another variant's same-named libraft.so if it's ever
# copied out of this directory by hand.
cp "${PROJECT_ROOT}/cpp/build-${GPU_TUNED_VARIANT}/libraft.so" "${PROJECT_ROOT}/cpp/build-${GPU_TUNED_VARIANT}/libraft_${GPU_TUNED_VARIANT}.so"
gpu_tuned_verify_arch "${PROJECT_ROOT}/cpp/build-${GPU_TUNED_VARIANT}/libraft_${GPU_TUNED_VARIANT}.so" || exit 1

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
objcopy --add-section .raft_build_info="${BUILD_INFO_FILE}" "${PROJECT_ROOT}/cpp/build-${GPU_TUNED_VARIANT}/libraft_${GPU_TUNED_VARIANT}.so"
rm -f "${BUILD_INFO_FILE}"
