#!/bin/bash
# raft_cupy_build_rtx40xx.sh — Build a CUDA-arch-specific cupy wheel for RTX
# 40xx (SM_89 / Ada Lovelace / x86_64) and place it in dist/rtx40xx/.
# Renamed from wsl/raft_cupy_build_wsl.sh.
#
# ── Why build from source? ────────────────────────────────────────────────────
# The official cupy-cuda13x PyPI wheel is ~73 MB (all arches).  Targeting
# SM_89 only produces ~10-20 MB — better for release assets.
#
# ── cupy and scipy are a pair ─────────────────────────────────────────────────
# cupyx.scipy.sparse requires scipy at *runtime* for CPU↔GPU sparse matrix
# conversions — not just for testing.  Always distribute and install cupy and
# scipy together.  See gb10/raft_cupy_build.sh for the full explanation.
# Reference: https://docs.cupy.dev/en/stable/install.html#python-dependencies
#
# ── Analogous scripts for other stacks ────────────────────────────────────────
#   gb10/raft_cupy_build.sh             — DGX Spark (SM_121a, aarch64)
#   rtx50xx/raft_cupy_build_rtx50xx.sh  — RTX 50xx  (SM_120,  x86_64)
#
# ── NOTE: untested — run on an x86_64 host with RTX 40xx + CUDA installed ────
#
# ── Usage ─────────────────────────────────────────────────────────────────────
#   bash rtx40xx/raft_cupy_build_rtx40xx.sh      # default version + output dir
#   CUPY_VERSION=14.0.1 bash rtx40xx/...         # pin a specific cupy version
#   DIST_DIR=/path/to/out bash rtx40xx/...       # override output directory
#   CUPY_NUM_BUILD_JOBS=16 bash rtx40xx/...      # parallel C++ compile jobs
#
# Environment variables honoured:
#   CUPY_VERSION          default: 14.0.1
#   CUDA_ARCH              default: 89  (SM_89 = Ada Lovelace / RTX 40xx)
#   DIST_DIR              default: <repo>/dist/rtx40xx
#   CUPY_NUM_BUILD_JOBS   default: $(nproc)
#   CUPY_NUM_NVCC_THREADS default: 2

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=raft_env_rtx40xx.sh
source "${PROJECT_ROOT}/rtx40xx/raft_env_rtx40xx.sh" || exit 1

CUPY_VERSION="${CUPY_VERSION:-14.0.1}"
CUDA_ARCH="${CUDA_ARCH:-${RTX40_CUDA_ARCH}}"
DIST_DIR="${DIST_DIR:-${PROJECT_ROOT}/dist/rtx40xx}"
JOBS="${CUPY_NUM_BUILD_JOBS:-$(nproc)}"
NVCC_THREADS="${CUPY_NUM_NVCC_THREADS:-2}"
CUPY_NVCC_GENERATE_CODE="arch=compute_${CUDA_ARCH},code=sm_${CUDA_ARCH}"

mkdir -p "${DIST_DIR}"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Building cupy-${CUPY_VERSION} for SM_${CUDA_ARCH} (RTX 40xx / Ada)"
echo "  CUDA:    ${CUDA_VERSION} (${CUDA_HOME})"
echo "  Python:  $(python3 --version)"
echo "  Arch:    $(uname -m)"
echo "  Output:  ${DIST_DIR}"
echo "  Jobs:    ${JOBS} build / ${NVCC_THREADS} nvcc threads"
echo "  CUPY_NVCC_GENERATE_CODE: ${CUPY_NVCC_GENERATE_CODE}"
echo "════════════════════════════════════════════════════════════════"

rm -f "${DIST_DIR}"/cupy-${CUPY_VERSION}-*.whl \
      "${DIST_DIR}"/cupy_cuda13x-${CUPY_VERSION}-*.whl

CUPY_NVCC_GENERATE_CODE="${CUPY_NVCC_GENERATE_CODE}" \
CUPY_NUM_BUILD_JOBS="${JOBS}" \
CUPY_NUM_NVCC_THREADS="${NVCC_THREADS}" \
CUDA_PATH="${CUDA_HOME}" \
    pip wheel --no-deps \
        "cupy==${CUPY_VERSION}" \
        -w "${DIST_DIR}"

WHEEL="$(ls "${DIST_DIR}"/cupy-${CUPY_VERSION}-*.whl 2>/dev/null | head -1)"
[[ -z "${WHEEL}" ]] && { echo "ERROR: cupy wheel not found after build." >&2; exit 1; }

SIZE="$(du -sh "${WHEEL}" | awk '{print $1}')"
echo ""
echo "Built: $(basename "${WHEEL}")  (${SIZE})"
echo ""
echo "  NOTE: Always distribute cupy alongside scipy."
echo "        Run: pip download --no-deps scipy -d ${DIST_DIR}"
echo ""
echo "Done."
