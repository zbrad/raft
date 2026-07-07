#!/bin/bash
# raft_cupy_build.sh — Build a CUDA-arch-specific cupy wheel for the DGX Spark
# stack (SM_121a / aarch64 / CUDA 13.2) and place it in dist/gb10/.
#
# ── Why build from source instead of the PyPI wheel? ─────────────────────────
# The official cupy-cuda13x PyPI wheel bundles pre-compiled SASS for every
# NVIDIA GPU arch, making it ~73 MB compressed.  Targeting SM_121a only
# produces a ~10-20 MB wheel — important for release asset size and deployment
# footprint, especially on embedded platforms like DGX Spark.
#
# ── cupy and scipy are a pair ─────────────────────────────────────────────────
# cupyx.scipy.sparse — cupy's GPU-accelerated sparse linear-algebra module —
# requires scipy at *runtime* for CPU↔GPU sparse matrix conversions, not just
# for testing.  For example, test_sparse.py fails at collection time with a
# plain ModuleNotFoundError if scipy is absent, even though scipy itself is a
# CPU-only library.  Always distribute and install cupy and scipy together.
# Reference: https://docs.cupy.dev/en/stable/install.html#python-dependencies
#
# ── Analogous scripts for other stacks ────────────────────────────────────────
#   wsl/raft_cupy_build_wsl.sh        — RTX 40xx  (SM_89,   x86_64, CUDA 13.2)
#   wsl/raft_cupy_build_rtx50xx.sh    — RTX 50xx  (SM_120, x86_64, CUDA 13.2)
#
# ── Usage ─────────────────────────────────────────────────────────────────────
#   bash gb10/raft_cupy_build.sh               # default version + output dir
#   CUPY_VERSION=14.0.1 bash gb10/...          # pin a specific cupy version
#   DIST_DIR=/path/to/out bash gb10/...        # override output directory
#   CUPY_NUM_BUILD_JOBS=16 bash gb10/...       # parallel C++ compile jobs
#
# Environment variables honoured:
#   CUPY_VERSION         default: 14.0.1
#   CUDA_ARCH            default: 121a  (SM_121a = DGX Spark / GB10)
#   DIST_DIR             default: <repo>/dist/gb10
#   CUPY_NUM_BUILD_JOBS  default: $(nproc)
#   CUPY_NUM_NVCC_THREADS default: 2

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=raft_env_gb10.sh
source "${PROJECT_ROOT}/gb10/raft_env_gb10.sh" || exit 1

CUPY_VERSION="${CUPY_VERSION:-14.0.1}"
CUDA_ARCH="${CUDA_ARCH:-${GB10_CUDA_ARCH}}"
DIST_DIR="${DIST_DIR:-${PROJECT_ROOT}/dist/gb10}"
JOBS="${CUPY_NUM_BUILD_JOBS:-$(nproc)}"
NVCC_THREADS="${CUPY_NUM_NVCC_THREADS:-2}"

# SM_121a uses compute_121a virtual arch and sm_121a real arch (the "a" selects
# Blackwell family-specific instructions -- see gb10/raft_env_gb10.sh for why).
# For SM_120 (RTX 50xx) the virtual arch is compute_120, real arch sm_120 (no
# "a", consumer silicon) — see wsl/raft_cupy_build_rtx50xx.sh for that variant.
CUPY_NVCC_GENERATE_CODE="arch=compute_${CUDA_ARCH},code=sm_${CUDA_ARCH}"

mkdir -p "${DIST_DIR}"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Building cupy-${CUPY_VERSION} for SM_${CUDA_ARCH}"
echo "  CUDA:    ${CUDA_VERSION} (${CUDA_HOME})"
echo "  Python:  $(python3 --version)"
echo "  Output:  ${DIST_DIR}"
echo "  Jobs:    ${JOBS} build / ${NVCC_THREADS} nvcc threads"
echo "  CUPY_NVCC_GENERATE_CODE: ${CUPY_NVCC_GENERATE_CODE}"
echo "════════════════════════════════════════════════════════════════"

# Remove any stale cupy wheel for this version so the output is deterministic.
# Source-built wheel is named 'cupy-VERSION-...' (package name 'cupy'), whereas
# the PyPI binary download is 'cupy_cuda13x-VERSION-...' — both are handled by
# the glob in raft_container_gb10.sh.
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
if [[ -z "${WHEEL}" ]]; then
    echo "ERROR: cupy wheel not found in ${DIST_DIR} after build." >&2
    exit 1
fi

SIZE="$(du -sh "${WHEEL}" | awk '{print $1}')"
echo ""
echo "Built: $(basename "${WHEEL}")  (${SIZE})"
echo ""
echo "  NOTE: Always distribute and install cupy alongside scipy."
echo "        cupyx.scipy.sparse requires scipy at runtime — not just for tests."
echo "        Run: pip download --no-deps scipy -d ${DIST_DIR}"
echo "        or:  bash gb10/raft_wheel_gb10.sh  (includes scipy download)"
echo ""
echo "Done."
