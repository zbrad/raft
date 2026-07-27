#!/bin/bash
# raft_full_test_rtx40xx.sh — thin wrapper; see gpu_tuned/gpu_tuned_full_test.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gpu_tuned/gpu_tuned_full_test.sh" rtx40xx "$@"
