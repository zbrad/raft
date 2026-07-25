#!/bin/bash
# raft_full_test_gb10.sh — run every built gtest binary for GB10
# (cpp/build-<arch>/gtests/*), not just the 2 targeted checks in
# raft_regression_test_gb10.sh. Slower and comprehensive; run this
# before a release, not on every iteration.
#
# NOTE: untested — run on an aarch64 host with GB10 + CUDA installed.
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="$(uname -m)"
# shellcheck source=../raft_test_common.sh
source "${PROJECT_ROOT}/raft_test_common.sh" || exit 1

run_full_test_suite "${PROJECT_ROOT}/cpp/build-${ARCH}"
