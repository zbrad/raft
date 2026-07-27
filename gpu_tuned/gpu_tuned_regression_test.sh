#!/bin/bash
# gpu_tuned_regression_test.sh <variant> — run the two targeted regression
# tests for the given GPU variant: UTILS_TEST (warpReduce ADL fix) and
# LINALG_TEST (laplacian NZType / SM_121a memory-corruption fix) -- the
# two known upstream bugs this fork carries fixes for. NOT a full test
# suite; see gpu_tuned_full_test.sh for that (runs every built gtest
# binary). Shared implementation behind every
# gb10/rtx40xx/rtx50xx raft_regression_test_<variant>.sh wrapper.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GPU_TUNED_ARG_VARIANT="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}/cpp/build-${GPU_TUNED_ARG_VARIANT}"
echo "=== UTILS_TEST (warpReduce regression) ==="
./gtests/UTILS_TEST
echo "=== LINALG_TEST (add_op / reduction) ==="
./gtests/LINALG_TEST
