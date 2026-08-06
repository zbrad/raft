#!/bin/bash
# raft_full_test_rtx50.sh — thin wrapper; see full_test.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/full_test.sh" rtx50 "$@"
