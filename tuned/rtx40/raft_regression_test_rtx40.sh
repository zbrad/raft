#!/bin/bash
# raft_regression_test_rtx40.sh — thin wrapper; see regression_test.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/regression_test.sh" rtx40 "$@"
