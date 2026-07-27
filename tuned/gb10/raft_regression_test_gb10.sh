#!/bin/bash
# raft_regression_test_gb10.sh — thin wrapper; see regression_test.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/regression_test.sh" gb10 "$@"
