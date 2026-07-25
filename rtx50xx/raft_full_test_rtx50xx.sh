#!/bin/bash
# raft_full_test_rtx50xx.sh — run every built gtest binary for RTX 50xx
# (cpp/build-rtx50xx/gtests/*), not just the 2 targeted checks in
# raft_regression_test_rtx50xx.sh. Slower and comprehensive; run this
# before a release, not on every iteration.
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../raft_test_common.sh
source "${PROJECT_ROOT}/raft_test_common.sh" || exit 1

run_full_test_suite "${PROJECT_ROOT}/cpp/build-rtx50xx"
