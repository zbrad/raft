#!/bin/bash
# raft_test_rtx40xx.sh — run gtests built for RTX 40xx.
# Renamed from wsl/raft_test_wsl.sh, which pointed at the generic cpp/build/
# directory. Fixed to point at cpp/build-rtx40xx, since RTX 40xx and RTX 50xx
# share uname -m == x86_64 and would otherwise collide on the same build dir.
#
# NOTE: untested — run on an x86_64 host with RTX 40xx + CUDA installed.
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}/cpp/build-rtx40xx"
echo "=== UTILS_TEST (warpReduce regression) ==="
./gtests/UTILS_TEST
echo "=== LINALG_TEST (add_op / reduction) ==="
./gtests/LINALG_TEST
