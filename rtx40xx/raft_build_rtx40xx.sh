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

verify_rtx40xx_arch "${PROJECT_ROOT}/cpp/build-${ARCH}/libraft.so" || exit 1
