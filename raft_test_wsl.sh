#!/bin/bash
export PATH=/home/zbrad/.local/bin:/usr/local/cuda-13.2/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${PROJECT_ROOT}/cpp/build"
echo "=== UTILS_TEST (warpReduce regression) ==="
./gtests/UTILS_TEST
echo "=== LINALG_TEST (add_op / reduction) ==="
./gtests/LINALG_TEST
