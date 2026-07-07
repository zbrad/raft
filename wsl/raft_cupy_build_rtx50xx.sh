#!/bin/bash
# raft_cupy_build_rtx50xx.sh — Build a CUDA-arch-specific cupy wheel for RTX 50xx
# (SM_120 / Blackwell consumer / x86_64 / CUDA 13.2) and place it in dist/rtx50xx/.
#
# ── Why build from source? ────────────────────────────────────────────────────
# The official cupy-cuda13x PyPI wheel is ~73 MB (all arches).  Targeting
# SM_120 only produces ~10-20 MB — better for release assets.
#
# ── SM_120 architecture note ─────────────────────────────────────────────────
# RTX 5000 series (Blackwell consumer) uses sm_120.  The virtual (PTX) arch
# is compute_120; the real arch target is sm_120:
#   CUPY_NVCC_GENERATE_CODE="arch=compute_120,code=sm_120"
# This is different from data-centre Blackwell (SM_100/SM_101) and from the
# DGX Spark GB10 (SM_121).
#
# ── cupy and scipy are a pair ─────────────────────────────────────────────────
# cupyx.scipy.sparse requires scipy at *runtime* for CPU↔GPU sparse matrix
# conversions — not just for testing.  Always distribute and install cupy and
# scipy together.  See gb10/raft_cupy_build.sh for the full explanation.
# Reference: https://docs.cupy.dev/en/stable/install.html#python-dependencies
#
# ── Analogous scripts for other stacks ────────────────────────────────────────
#   gb10/raft_cupy_build.sh            — DGX Spark (SM_121,  aarch64, CUDA 13.2)
#   wsl/raft_cupy_build_wsl.sh         — RTX 40xx  (SM_89,   x86_64,  CUDA 13.2)
#
# ── NOTE: untested — run on an x86_64 host with RTX 50xx + CUDA 13.2 ─────────
#
# ── Usage ─────────────────────────────────────────────────────────────────────
#   bash wsl/raft_cupy_build_rtx50xx.sh          # default version + output dir
#   CUPY_VERSION=14.0.1 bash wsl/...             # pin a specific cupy version
#   DIST_DIR=/path/to/out bash wsl/...           # override output directory
#
# Environment variables honoured:
#   CUPY_VERSION          default: 14.0.1
#   DIST_DIR              default: <repo>/dist/rtx50xx
#   CUPY_NUM_BUILD_JOBS   default: $(nproc)
#   CUPY_NUM_NVCC_THREADS default: 2

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PATH="${PATH}:/usr/local/cuda-13.2/bin:/usr/local/cuda/bin"
CUDA_HOME="${CUDA_HOME:-/usr/local/cuda-13.2}"
if [[ ! -x "${CUDA_HOME}/bin/nvcc" ]] && command -v nvcc &>/dev/null; then
    CUDA_HOME="$(dirname "$(dirname "$(command -v nvcc)")")"
fi
if [[ ! -x "${CUDA_HOME}/bin/nvcc" ]]; then
    echo "ERROR: nvcc not found. Set CUDA_HOME or ensure nvcc is on PATH." >&2
    exit 1
fi
CUDA_VERSION="$("${CUDA_HOME}/bin/nvcc" --version | sed -n 's/.*release \([0-9.]*\).*/\1/p')"

CUPY_VERSION="${CUPY_VERSION:-14.0.1}"
DIST_DIR="${DIST_DIR:-${PROJECT_ROOT}/dist/rtx50xx}"
JOBS="${CUPY_NUM_BUILD_JOBS:-$(nproc)}"
NVCC_THREADS="${CUPY_NUM_NVCC_THREADS:-2}"

# RTX 50xx Blackwell: virtual arch compute_120, real arch sm_120.
CUPY_NVCC_GENERATE_CODE="arch=compute_120,code=sm_120"

mkdir -p "${DIST_DIR}"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Building cupy-${CUPY_VERSION} for SM_120 (RTX 50xx / Blackwell)"
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
