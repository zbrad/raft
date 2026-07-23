#!/bin/bash
# raft_build_rtx50xx.sh — build libraft + tests for RTX 50xx (SM_120, x86_64).
# New script — previously only the cupy build was split out per-GPU for RTX
# 50xx; the C++ build had no separate/pinned-arch script of its own.
#
# NOTE: untested — run on an x86_64 host with RTX 50xx + CUDA installed.
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="rtx50xx"
# shellcheck source=raft_env_rtx50xx.sh
source "${PROJECT_ROOT}/rtx50xx/raft_env_rtx50xx.sh" || exit 1
cd "${PROJECT_ROOT}"
LIBRAFT_BUILD_DIR="${PROJECT_ROOT}/cpp/build-${ARCH}" bash build.sh libraft tests --compile-lib --cache-tool=ccache "--cmake-args=\"-DCMAKE_CUDA_ARCHITECTURES=${RTX50_CUDA_ARCH}\""

# Copy (not rename) alongside the bare libraft.so: raft_wheel_rtx50xx.sh's
# later `cmake --install` still needs the original bare-named file at this
# exact path (baked into cmake_install.cmake at configure time). The
# variant-qualified copy exists purely so this build's own artifact can't
# get confused with another variant's same-named libraft.so if it's ever
# copied out of this directory by hand.
cp "${PROJECT_ROOT}/cpp/build-${ARCH}/libraft.so" "${PROJECT_ROOT}/cpp/build-${ARCH}/libraft_rtx50xx.so"
verify_rtx50xx_arch "${PROJECT_ROOT}/cpp/build-${ARCH}/libraft_rtx50xx.so" || exit 1
