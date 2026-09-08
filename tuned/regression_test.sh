#!/bin/bash
# regression_test.sh <variant> — run the two targeted regression
# tests for the given GPU variant: UTILS_TEST (warpReduce ADL fix) and
# SPARSE_TEST (laplacian NZType / SM_121a memory-corruption fix) -- the
# two known upstream bugs this fork carries fixes for. NOT a full test
# suite; see full_test.sh for that (runs every built gtest
# binary). Shared implementation behind every
# gb10/rtx40/rtx50 raft_regression_test_<variant>.sh wrapper.
#
# Filtered to just the two regression tests, not every test in these
# binaries -- LINALG_TEST was wrong here until 2026-09-08 (the laplacian
# fix's test, cpp/tests/sparse/laplacian.cu, has always built into
# SPARSE_TEST per cpp/tests/CMakeLists.txt, never LINALG_TEST; caught by
# actually checking which CMake target the file belongs to before
# assuming the comment was right).
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GPU_TUNED_ARG_VARIANT="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}/cpp/build-${GPU_TUNED_ARG_VARIANT}"
echo "=== UTILS_TEST (warpReduce regression) ==="
./gtests/UTILS_TEST --gtest_filter="*WarpReduce*"
echo "=== SPARSE_TEST (laplacian NZType regression) ==="
./gtests/SPARSE_TEST --gtest_filter="Raft.ComputeGraphLaplacianCOOLongNZType"
