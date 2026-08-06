#!/bin/bash
# cupy_build.sh <variant> — Build a CUDA-arch-specific cupy
# wheel for the given GPU variant and place it in dist/<variant>/. Shared
# implementation behind every gb10/rtx40/rtx50
# raft_cupy_build_<variant>.sh wrapper.
#
# ── Why build from source instead of the PyPI wheel? ─────────────────────────
# The official cupy-cuda13x PyPI wheel bundles pre-compiled SASS for every
# NVIDIA GPU arch, making it ~73 MB compressed. Targeting a single SM arch
# produces a ~10-20 MB wheel — important for release asset size and
# deployment footprint, especially on embedded platforms like DGX Spark.
#
# ── cupy and scipy are a pair ─────────────────────────────────────────────────
# cupyx.scipy.sparse — cupy's GPU-accelerated sparse linear-algebra module —
# requires scipy at *runtime* for CPU↔GPU sparse matrix conversions, not just
# for testing. For example, test_sparse.py fails at collection time with a
# plain ModuleNotFoundError if scipy is absent, even though scipy itself is a
# CPU-only library. Always distribute and install cupy and scipy together.
# Reference: https://docs.cupy.dev/en/stable/install.html#python-dependencies
#
# ── Usage ─────────────────────────────────────────────────────────────────────
#   bash tuned/cupy_build.sh rtx50                    # default version + output dir
#   CUPY_VERSION=14.0.1 bash tuned/cupy_build.sh rtx50  # pin a specific cupy version
#   DIST_DIR=/path/to/out bash tuned/cupy_build.sh rtx50  # override output directory
#   CUPY_NUM_BUILD_JOBS=16 bash tuned/cupy_build.sh rtx50  # parallel C++ compile jobs
#
# Environment variables honoured:
#   CUPY_VERSION           default: 14.0.1
#   CUDA_ARCH               default: this variant's GPU_TUNED_CUDA_ARCH
#   DIST_DIR                default: <repo>/dist/<variant>
#   CUPY_NUM_BUILD_JOBS      default: $(nproc)
#   CUPY_NUM_NVCC_THREADS    default: 2

set -euo pipefail

GPU_TUNED_ARG_VARIANT="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1

CUPY_VERSION="${CUPY_VERSION:-14.0.1}"
CUDA_ARCH="${CUDA_ARCH:-${GPU_TUNED_CUDA_ARCH}}"
DIST_DIR="${DIST_DIR:-${PROJECT_ROOT}/dist/${GPU_TUNED_VARIANT}}"
JOBS="${CUPY_NUM_BUILD_JOBS:-$(nproc)}"
NVCC_THREADS="${CUPY_NUM_NVCC_THREADS:-2}"

# The virtual (PTX) arch and real arch match for every variant here (e.g.
# compute_121a/sm_121a for gb10, compute_120/sm_120 for rtx50) -- the
# "a" suffix (or lack of it) is exactly GPU_TUNED_CUDA_ARCH's own value,
# see tuned/devices/*.conf for why each variant needs what it needs.
CUPY_NVCC_GENERATE_CODE="arch=compute_${CUDA_ARCH},code=sm_${CUDA_ARCH}"

mkdir -p "${DIST_DIR}"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Building cupy-${CUPY_VERSION} for SM_${CUDA_ARCH} (${GPU_TUNED_HW_LABEL})"
echo "  CUDA:    ${CUDA_VERSION} (${CUDA_HOME})"
echo "  Python:  $(python3 --version)"
echo "  Arch:    $(uname -m)"
echo "  Output:  ${DIST_DIR}"
echo "  Jobs:    ${JOBS} build / ${NVCC_THREADS} nvcc threads"
echo "  CUPY_NVCC_GENERATE_CODE: ${CUPY_NVCC_GENERATE_CODE}"
echo "════════════════════════════════════════════════════════════════"

# Remove any stale cupy wheel for this version so the output is
# deterministic. Source-built wheel is named 'cupy-VERSION-...' (package
# name 'cupy'), whereas the PyPI binary download is
# 'cupy_cuda13x-VERSION-...' -- both globs are cleaned up here.
rm -f "${DIST_DIR}"/cupy-${CUPY_VERSION}-*.whl \
      "${DIST_DIR}"/cupy_cuda13x-${CUPY_VERSION}-*.whl

CUPY_NVCC_GENERATE_CODE="${CUPY_NVCC_GENERATE_CODE}" \
CUPY_NUM_BUILD_JOBS="${JOBS}" \
CUPY_NUM_NVCC_THREADS="${NVCC_THREADS}" \
CUDA_PATH="${CUDA_HOME}" \
    pip wheel --no-deps \
        "cupy==${CUPY_VERSION}" \
        -w "${DIST_DIR}"

WHEEL="$(ls "${DIST_DIR}"/cupy-${CUPY_VERSION}-*.whl 2>/dev/null | head -1)" || true
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
echo "        or:  bash tuned/${GPU_TUNED_VARIANT}/raft_wheel_${GPU_TUNED_VARIANT}.sh"
echo ""
echo "Done."
