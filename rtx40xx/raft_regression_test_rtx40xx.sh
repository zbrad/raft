#!/bin/bash
# raft_regression_test_rtx40xx.sh — thin wrapper; see gpu_tuned/gpu_tuned_regression_test.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gpu_tuned/gpu_tuned_regression_test.sh" rtx40xx "$@"
