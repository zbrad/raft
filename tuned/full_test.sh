#!/bin/bash
# full_test.sh <variant> — run every built gtest binary for the
# given GPU variant (cpp/build-<variant>/gtests/*), not just the 2
# targeted checks in regression_test.sh. Slower and
# comprehensive; run this before a release, not on every iteration.
# Shared implementation behind every
# gb10/rtx40/rtx50 raft_full_test_<variant>.sh wrapper.
#
# Writes a timestamped results log to tuned/releases/, which
# release.sh requires (fresher than the built .so, containing the
# success marker) before it will publish, and attaches as a release
# asset -- see release.sh's own comment for why.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GPU_TUNED_ARG_VARIANT="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=raft_test_common.sh
source "${PROJECT_ROOT}/tuned/raft_test_common.sh" || exit 1

mkdir -p "${PROJECT_ROOT}/tuned/releases"
RESULTS_FILE="${PROJECT_ROOT}/tuned/releases/TEST_RESULTS_${GPU_TUNED_ARG_VARIANT}.log"

{
    echo "raft full test suite -- variant=${GPU_TUNED_ARG_VARIANT}"
    echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "commit:  $(git -C "${PROJECT_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo ""
} > "${RESULTS_FILE}"

# set -o pipefail: without it, `run_full_test_suite | tee` always exits 0
# (the pipeline's exit status becomes tee's, not run_full_test_suite's) --
# release.sh's gate depends on this script's own exit code being the real
# pass/fail signal, not tee's.
set -o pipefail
run_full_test_suite "${PROJECT_ROOT}/cpp/build-${GPU_TUNED_ARG_VARIANT}" 2>&1 | tee -a "${RESULTS_FILE}"
STATUS=$?

echo "" >> "${RESULTS_FILE}"
echo "finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${RESULTS_FILE}"
echo "Results written to ${RESULTS_FILE}"
exit "${STATUS}"
