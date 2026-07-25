#!/bin/bash
# raft_regression_test_gb10.sh — run the two targeted regression tests
# for GB10: UTILS_TEST (warpReduce ADL fix) and LINALG_TEST (laplacian
# NZType / SM_121a memory-corruption fix) -- the two known upstream bugs
# this fork carries fixes for. NOT a full test suite; see
# raft_full_test_gb10.sh for that (runs every built gtest binary).
# Renamed from raft_test_gb10.sh to make this scope explicit.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="$(uname -m)"
cd "${PROJECT_ROOT}/cpp/build-${ARCH}"
echo "=== UTILS_TEST (warpReduce regression) ==="
./gtests/UTILS_TEST
echo "=== LINALG_TEST (add_op / reduction) ==="
./gtests/LINALG_TEST
