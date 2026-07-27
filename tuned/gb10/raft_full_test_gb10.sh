#!/bin/bash
# raft_full_test_gb10.sh — thin wrapper; see full_test.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/full_test.sh" gb10 "$@"
