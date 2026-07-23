#!/bin/bash
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="$(uname -m)"
# shellcheck source=raft_env_gb10.sh
source "${PROJECT_ROOT}/gb10/raft_env_gb10.sh" || exit 1
cd "${PROJECT_ROOT}"
LIBRAFT_BUILD_DIR="${PROJECT_ROOT}/cpp/build-${ARCH}" bash build.sh libraft tests --compile-lib --cache-tool=ccache "--cmake-args=\"-DCMAKE_CUDA_ARCHITECTURES=${GB10_CUDA_ARCH}\""

# Copy (not rename) alongside the bare libraft.so: raft_wheel_gb10.sh's
# later `cmake --install` still needs the original bare-named file at this
# exact path (baked into cmake_install.cmake at configure time). The
# variant-qualified copy exists purely so this build's own artifact can't
# get confused with another variant's same-named libraft.so if it's ever
# copied out of this directory by hand.
cp "${PROJECT_ROOT}/cpp/build-${ARCH}/libraft.so" "${PROJECT_ROOT}/cpp/build-${ARCH}/libraft_gb10.so"
verify_gb10_arch "${PROJECT_ROOT}/cpp/build-${ARCH}/libraft_gb10.so" || exit 1
