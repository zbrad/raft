#!/bin/bash
# raft_build_rtx40xx.sh — build libraft + tests for RTX 40xx (SM_89, x86_64).
# Renamed from wsl/raft_build_wsl.sh; previously built with no explicit arch
# pin at all (relied on implicit/native GPU detection). Now pins
# CMAKE_CUDA_ARCHITECTURES explicitly and verifies the result.
#
# NOTE: untested — run on an x86_64 host with RTX 40xx + CUDA installed.
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="rtx40xx"
# shellcheck source=raft_env_rtx40xx.sh
source "${PROJECT_ROOT}/rtx40xx/raft_env_rtx40xx.sh" || exit 1
cd "${PROJECT_ROOT}"
LIBRAFT_BUILD_DIR="${PROJECT_ROOT}/cpp/build-${ARCH}" bash build.sh libraft tests --compile-lib --cache-tool=ccache "--cmake-args=\"-DCMAKE_CUDA_ARCHITECTURES=${RTX40_CUDA_ARCH}\""

# Copy (not rename) alongside the bare libraft.so: raft_wheel_rtx40xx.sh's
# later `cmake --install` still needs the original bare-named file at this
# exact path (baked into cmake_install.cmake at configure time). The
# variant-qualified copy exists purely so this build's own artifact can't
# get confused with another variant's same-named libraft.so if it's ever
# copied out of this directory by hand.
cp "${PROJECT_ROOT}/cpp/build-${ARCH}/libraft.so" "${PROJECT_ROOT}/cpp/build-${ARCH}/libraft_rtx40xx.so"
verify_rtx40xx_arch "${PROJECT_ROOT}/cpp/build-${ARCH}/libraft_rtx40xx.so" || exit 1

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
echo "raft-rtx40xx build: https://github.com/zbrad/raft @ ${GIT_COMMIT}, CUDA ${CUDA_VERSION}, sm_${RTX40_CUDA_ARCH}, built ${BUILD_TIMESTAMP}" > "${BUILD_INFO_FILE}"
objcopy --add-section .raft_build_info="${BUILD_INFO_FILE}" "${PROJECT_ROOT}/cpp/build-${ARCH}/libraft_rtx40xx.so"
rm -f "${BUILD_INFO_FILE}"
