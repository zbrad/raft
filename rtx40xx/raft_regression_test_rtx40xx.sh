#!/bin/bash
# raft_regression_test_rtx40xx.sh — run the two targeted regression tests
# for RTX 40xx: UTILS_TEST (warpReduce ADL fix) and LINALG_TEST (laplacian
# NZType / SM_121a memory-corruption fix) -- the two known upstream bugs
# this fork carries fixes for. NOT a full test suite; see
# raft_full_test_rtx40xx.sh for that (runs every built gtest binary).
# Renamed from raft_test_rtx40xx.sh to make this scope explicit.
#
# Split out of the old generic wsl/raft_test_wsl.sh, which pointed at
# cpp/build/ with no per-GPU variant. Points at cpp/build-rtx40xx, since RTX
# 40xx and RTX 50xx share uname -m == x86_64 and would otherwise collide on
# the same build dir.
#
# NOTE: untested — run on an x86_64 host with RTX 40xx + CUDA installed.
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}/cpp/build-rtx40xx"
echo "=== UTILS_TEST (warpReduce regression) ==="
./gtests/UTILS_TEST
echo "=== LINALG_TEST (add_op / reduction) ==="
./gtests/LINALG_TEST
