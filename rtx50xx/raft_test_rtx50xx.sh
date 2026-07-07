#!/bin/bash
# raft_test_rtx50xx.sh — run gtests built for RTX 50xx.
# New (split out of the old generic wsl/raft_test_wsl.sh, which pointed at
# cpp/build/ with no per-GPU variant). Points at cpp/build-rtx50xx, since RTX
# 40xx and RTX 50xx share uname -m == x86_64 and would otherwise collide on
# the same build dir.
#
# NOTE: untested — run on an x86_64 host with RTX 50xx + CUDA installed.
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}/cpp/build-rtx50xx"
echo "=== UTILS_TEST (warpReduce regression) ==="
./gtests/UTILS_TEST
echo "=== LINALG_TEST (add_op / reduction) ==="
./gtests/LINALG_TEST
