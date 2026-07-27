#!/bin/bash
# gpu_tuned_full_test.sh <variant> — run every built gtest binary for the
# given GPU variant (cpp/build-<variant>/gtests/*), not just the 2
# targeted checks in gpu_tuned_regression_test.sh. Slower and
# comprehensive; run this before a release, not on every iteration.
# Shared implementation behind every
# gb10/rtx40xx/rtx50xx raft_full_test_<variant>.sh wrapper.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GPU_TUNED_ARG_VARIANT="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../raft_test_common.sh
source "${PROJECT_ROOT}/raft_test_common.sh" || exit 1

run_full_test_suite "${PROJECT_ROOT}/cpp/build-${GPU_TUNED_ARG_VARIANT}"
