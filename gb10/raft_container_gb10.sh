#!/bin/bash
# raft_container_gb10.sh — Build, smoke-test, and optionally gtest the
# cuda13.2-pip-spark devcontainer image for DGX Spark (SM_121a / aarch64 / CUDA 13.2).
#
# Usage:
#   bash gb10/raft_container_gb10.sh           # all phases: build → smoke → test → pytest
#   bash gb10/raft_container_gb10.sh --build   # build image only
#   bash gb10/raft_container_gb10.sh --smoke   # smoke test only (no GPU needed)
#   bash gb10/raft_container_gb10.sh --test    # gtest only (requires SM_121a GPU)
#   bash gb10/raft_container_gb10.sh --pytest  # Python tests via pylibraft-gb10-cu13 wheel
#
# Environment variables:
#   SKIP_GPU_TEST=1   Skip gtest and pytest phases even when --test/--pytest are passed.
#   IMAGE_TAG         Override the output image tag (default: raft-cuda13.2-pip-spark:26.06).
#   DIST_DIR          Path to directory containing the gb10 wheels (default: <repo>/dist/gb10).
#
# ── Test dependencies: cupy and scipy ────────────────────────────────────────
# The pytest phase requires cupy-cuda13x and scipy in DIST_DIR alongside the raft
# wheels.  By default it auto-downloads the PyPI binaries (~73 MB cupy + ~33 MB
# scipy) if they are not already cached there.
#
# For a smaller arch-specific cupy wheel (~10-20 MB, SM_121a only), build from
# source first:
#   bash gb10/raft_cupy_build.sh         # outputs cupy_cuda13x-*.whl to dist/gb10/
#   pip download --no-deps scipy -d dist/gb10/
# Then re-run --pytest; it will pick up the local wheels automatically.
#
# scipy is required not just for testing but at runtime by cupyx.scipy.sparse
# (cupy's GPU sparse linear-algebra module).  Always distribute cupy and scipy
# together.  See gb10/raft_cupy_build.sh for the full explanation.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVCONTAINER_CONFIG="${PROJECT_ROOT}/.devcontainer/cuda13.2-pip-spark/devcontainer.json"
IMAGE_TAG="${IMAGE_TAG:-raft-cuda13.2-pip-spark:26.06}"
# Must match GB10_CUDA_ARCH in gb10/raft_env_gb10.sh (not sourced here since
# this script only drives docker and needs no local CUDA toolkit).
CUDA_ARCH="121a"

# ── parse flags ────────────────────────────────────────────────────────────────
DO_BUILD=0
DO_SMOKE=0
DO_TEST=0
DO_PYTEST=0

if [[ $# -eq 0 ]]; then
    DO_BUILD=1; DO_SMOKE=1; DO_TEST=1; DO_PYTEST=1
fi

for arg in "$@"; do
    case "${arg}" in
        --build)  DO_BUILD=1  ;;
        --smoke)  DO_SMOKE=1  ;;
        --test)   DO_TEST=1   ;;
        --pytest) DO_PYTEST=1 ;;
        *) echo "Unknown flag: ${arg}"; echo "Usage: $0 [--build] [--smoke] [--test] [--pytest]"; exit 1 ;;
    esac
done

# ── phase 0: ensure devcontainer CLI ──────────────────────────────────────────
require_devcontainer_cli() {
    if command -v devcontainer &>/dev/null; then
        echo "devcontainer CLI: $(devcontainer --version)"
        return 0
    fi
    echo "devcontainer CLI not found — installing via npm..."
    if ! command -v npm &>/dev/null; then
        echo "ERROR: npm is required to install @devcontainers/cli." >&2
        echo "       Install Node.js >=18 then re-run, or install manually:" >&2
        echo "       npm install -g @devcontainers/cli" >&2
        exit 1
    fi
    npm install -g @devcontainers/cli
    echo "devcontainer CLI: $(devcontainer --version)"
}

# ── phase 1: build ─────────────────────────────────────────────────────────────
phase_build() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  PHASE 1 — Build image: ${IMAGE_TAG}"
    echo "  Config:  ${DEVCONTAINER_CONFIG}"
    echo "════════════════════════════════════════════════════════════════"
    require_devcontainer_cli
    devcontainer build \
        --workspace-folder "${PROJECT_ROOT}" \
        --config "${DEVCONTAINER_CONFIG}" \
        --image-name "${IMAGE_TAG}"
    echo ""
    echo "Build complete. Image: ${IMAGE_TAG}"
    docker images "${IMAGE_TAG%%:*}" --format "  {{.Repository}}:{{.Tag}}  size={{.Size}}  created={{.CreatedSince}}"
}

# ── phase 2: smoke test ────────────────────────────────────────────────────────
phase_smoke() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  PHASE 2 — Smoke test (no GPU required)"
    echo "  Image:   ${IMAGE_TAG}"
    echo "════════════════════════════════════════════════════════════════"

    SMOKE_SCRIPT=$(cat <<'SMOKE'
set -euo pipefail
PASS=0; FAIL=0; WARN=0

check() {
    local label="$1"; shift
    if "$@" &>/dev/null; then
        echo "  PASS  ${label}"
        PASS=$((PASS+1))
    else
        echo "  FAIL  ${label}"
        FAIL=$((FAIL+1))
    fi
}

check_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "${actual}" == "${expected}" ]]; then
        echo "  PASS  ${label} = ${actual}"
        PASS=$((PASS+1))
    else
        echo "  FAIL  ${label}: expected '${expected}', got '${actual}'"
        FAIL=$((FAIL+1))
    fi
}

# Soft check: logs WARN but does not fail the suite.
# RAPIDS Python packages are installed by postAttachCommand, not baked into
# the image, so their absence here is expected and not an error.
check_warn() {
    local label="$1"; shift
    if "$@" &>/dev/null; then
        echo "  PASS  ${label}"
        PASS=$((PASS+1))
    else
        echo "  WARN  ${label} (post-attach package, expected absent in plain image)"
        WARN=$((WARN+1))
    fi
}

# ── image-level checks (hard failures) ──────────────────────────────────────
check_eq "CUDAARCHS"              "121a" "${CUDAARCHS:-}"
check_eq "PYTHON_PACKAGE_MANAGER" "pip"  "${PYTHON_PACKAGE_MANAGER:-}"
check    "nvcc present"           which nvcc
check    "nvcc executes"          nvcc --version
check    "python3 present"        which python3
check    "python3 executes"       python3 --version
check    "pip present"            which pip
check    "rapids-build-utils CLI" sh -c "command -v rapids-dependency-file-generator || command -v rapids-build-utils"

# ── Python >= 3.14 version check ─────────────────────────────────────────────
PY_MAJOR=$(python3 -c "import sys; print(sys.version_info.major)")
PY_MINOR=$(python3 -c "import sys; print(sys.version_info.minor)")
PY_VER="${PY_MAJOR}.${PY_MINOR}"
if [[ "${PY_MAJOR}" -gt 3 ]] || { [[ "${PY_MAJOR}" -eq 3 ]] && [[ "${PY_MINOR}" -ge 14 ]]; }; then
    echo "  PASS  python3 >= 3.14 (found ${PY_VER})"
    PASS=$((PASS+1))
else
    echo "  FAIL  python3 >= 3.14 required (found ${PY_VER})"
    FAIL=$((FAIL+1))
fi

# ── post-attach checks (soft warnings) ───────────────────────────────────────
echo ""
echo "  (post-attach checks — WARN is expected for a freshly built image)"
check_warn "cuda-python importable" python3 -c "import cuda"
check_warn "librmm-cu13 installed"  pip show librmm-cu13
check_warn "rmm-cu13 installed"     pip show rmm-cu13

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed, ${WARN} warned (post-attach)"
[[ ${FAIL} -eq 0 ]]
SMOKE
)

    docker run --rm \
        -e CUDAARCHS="${CUDA_ARCH}" \
        -e PYTHON_PACKAGE_MANAGER=pip \
        "${IMAGE_TAG}" \
        bash -c "${SMOKE_SCRIPT}"
    echo ""
    echo "Smoke test passed."
}

# ── phase 3: gtest suite ───────────────────────────────────────────────────────
phase_test() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  PHASE 3 — gtest suite (requires SM_121a GPU)"
    echo "  Image:   ${IMAGE_TAG}"
    echo "════════════════════════════════════════════════════════════════"

    if [[ "${SKIP_GPU_TEST:-0}" == "1" ]]; then
        echo "  SKIPPED — SKIP_GPU_TEST=1"
        return 0
    fi

    # Verify GPU access
    if ! docker run --rm --gpus all "${IMAGE_TAG}" nvidia-smi -L &>/dev/null; then
        echo "  WARNING: No GPU available via --gpus all. Skipping gtest phase."
        echo "           To run on a machine with SM_121a hardware, re-run with --test."
        return 0
    fi

    # The gtest phase runs pre-built binaries from the host's build dir inside
    # the container. This validates that SM_121a binaries execute correctly in
    # the containerised environment without needing internet or a full rebuild.
    ARCH="$(uname -m)"
    HOST_BUILD_DIR="${PROJECT_ROOT}/cpp/build-${ARCH}"
    CONTAINER_BUILD_DIR="/home/coder/raft/cpp/build-${ARCH}"

    if [[ ! -f "${HOST_BUILD_DIR}/gtests/UTILS_TEST" ]] || \
       [[ ! -f "${HOST_BUILD_DIR}/gtests/LINALG_TEST" ]]; then
        echo "  WARNING: Pre-built gtests not found at ${HOST_BUILD_DIR}/gtests/"
        echo "           Run 'bash gb10/raft_build_gb10.sh' on the host first, then re-run --test."
        return 0
    fi

    docker run --rm \
        --gpus all \
        -e CUDAARCHS="${CUDA_ARCH}" \
        -e PYTHON_PACKAGE_MANAGER=pip \
        -e LD_LIBRARY_PATH="${CONTAINER_BUILD_DIR}/install/lib:${CONTAINER_BUILD_DIR}/_deps/rmm-build" \
        -v "${PROJECT_ROOT}:/home/coder/raft" \
        -w /home/coder/raft \
        "${IMAGE_TAG}" \
        bash -c "
            set -euo pipefail
            echo '=== UTILS_TEST (warpReduce regression) ==='
            ${CONTAINER_BUILD_DIR}/gtests/UTILS_TEST
            echo '=== LINALG_TEST (add_op / reduction) ==='
            ${CONTAINER_BUILD_DIR}/gtests/LINALG_TEST
        "
    echo ""
    echo "gtest suite passed."
}

# ── phase 4: Python tests via pylibraft-gb10-cu13 wheel ──────────────────────
phase_pytest() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  PHASE 4 — Python tests (pylibraft-gb10-cu13, requires SM_121a GPU)"
    echo "  Image:   ${IMAGE_TAG}"
    echo "════════════════════════════════════════════════════════════════"

    if [[ "${SKIP_GPU_TEST:-0}" == "1" ]]; then
        echo "  SKIPPED — SKIP_GPU_TEST=1"
        return 0
    fi

    DIST_DIR="${DIST_DIR:-${PROJECT_ROOT}/dist/gb10}"
    LIBRAFT_WHL="$(ls "${DIST_DIR}"/libraft_gb10_cu13-*.whl 2>/dev/null | head -1)" || true
    PYLIBRAFT_WHL="$(ls "${DIST_DIR}"/pylibraft_gb10_cu13-*.whl 2>/dev/null | head -1)" || true

    if [[ -z "${LIBRAFT_WHL}" ]] || [[ -z "${PYLIBRAFT_WHL}" ]]; then
        echo "  WARNING: pylibraft-gb10-cu13 wheels not found in ${DIST_DIR}."
        echo "           Run 'bash gb10/raft_wheel_gb10.sh' first to build them."
        return 0
    fi
    echo "  libraft wheel:   $(basename "${LIBRAFT_WHL}")"
    echo "  pylibraft wheel: $(basename "${PYLIBRAFT_WHL}")"

    # Ensure test-only deps (cupy, scipy) are cached in dist/gb10 so
    # the container never needs outbound PyPI access during the test phase.
    # Prefer a source-built arch-specific wheel (gb10/raft_cupy_build.sh) if
    # present; fall back to downloading the PyPI binary.
    if ! ls "${DIST_DIR}"/cupy-*.whl &>/dev/null && ! ls "${DIST_DIR}"/cupy_cuda13x-*.whl &>/dev/null || \
       ! ls "${DIST_DIR}"/scipy-*.whl &>/dev/null; then
        echo "  Downloading test deps (cupy-cuda13x, scipy) into ${DIST_DIR}..."
        pip download --quiet --no-deps cupy-cuda13x scipy -d "${DIST_DIR}"
    fi
    # Preference order for cupy wheel:
    #   1. cupy-*.whl        — source-built SM_121a-only (gb10/raft_cupy_build.sh), ~36 MB
    #   2. cupy_cuda13x-*.whl — PyPI binary w/ all arches (auto-downloaded below), ~73 MB
    # Note: pip validates that the dist-info name matches the wheel filename, so the
    # source-built wheel keeps its 'cupy' package name.  The stack is identified by
    # its location in dist/gb10/ — not its filename.
    CUPY_WHL="$(ls "${DIST_DIR}"/cupy-*.whl 2>/dev/null | head -1)" || true
    if [[ -z "${CUPY_WHL}" ]]; then
        CUPY_WHL="$(ls "${DIST_DIR}"/cupy_cuda13x-*.whl 2>/dev/null | head -1)" || true
    fi
    SCIPY_WHL="$(ls "${DIST_DIR}"/scipy-*.whl 2>/dev/null | head -1)" || true
    echo "  cupy wheel:      $(basename "${CUPY_WHL}")"
    echo "  scipy wheel:     $(basename "${SCIPY_WHL}")"

    # Verify GPU access
    if ! docker run --rm --gpus all "${IMAGE_TAG}" nvidia-smi -L &>/dev/null; then
        echo "  WARNING: No GPU available via --gpus all. Skipping pytest phase."
        return 0
    fi

    LIBRAFT_WHL_BASE="$(basename "${LIBRAFT_WHL}")"
    PYLIBRAFT_WHL_BASE="$(basename "${PYLIBRAFT_WHL}")"
    CUPY_WHL_BASE="$(basename "${CUPY_WHL}")"
    SCIPY_WHL_BASE="$(basename "${SCIPY_WHL}")"
    CONTAINER_DIST="/tmp/gb10-wheels"

    docker run --rm \
        --gpus all \
        -e CUDAARCHS="${CUDA_ARCH}" \
        -e PYTHON_PACKAGE_MANAGER=pip \
        -v "${PROJECT_ROOT}:/home/coder/raft" \
        -v "${DIST_DIR}:${CONTAINER_DIST}:ro" \
        -w /home/coder/raft \
        "${IMAGE_TAG}" \
        bash -c "
            set -euo pipefail

            # Require Python >= 3.14 (cuda-python 13.x and pylibraft-gb10-cu13 abi3
            # wheels are built against CP311 but the DGX Spark runtime is 3.14; older
            # versions may silently load wrong ABI or fail to import CUDA extensions).
            PY_MAJOR=\$(python3 -c 'import sys; print(sys.version_info.major)')
            PY_MINOR=\$(python3 -c 'import sys; print(sys.version_info.minor)')
            if [[ \"\${PY_MAJOR}\" -lt 3 ]] || { [[ \"\${PY_MAJOR}\" -eq 3 ]] && [[ \"\${PY_MINOR}\" -lt 14 ]]; }; then
                echo \"ERROR: Python >= 3.14 required for DGX Spark wheels (found \${PY_MAJOR}.\${PY_MINOR})\" >&2
                exit 1
            fi
            echo \"Python \${PY_MAJOR}.\${PY_MINOR} — OK\"

            echo '--- Installing gb10 wheels and runtime deps ---'
            pip install --quiet \
                --extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple \
                pytest \
                '${CONTAINER_DIST}/${CUPY_WHL_BASE}' \
                '${CONTAINER_DIST}/${SCIPY_WHL_BASE}' \
                -r /home/coder/raft/requirements-build-cuda13.txt \
                '${CONTAINER_DIST}/${LIBRAFT_WHL_BASE}' \
                '${CONTAINER_DIST}/${PYLIBRAFT_WHL_BASE}'
            echo '--- Installed packages ---'
            pip show libraft-gb10-cu13 pylibraft-gb10-cu13
            echo '--- Running pylibraft tests ---'
            cd /home/coder/raft/python/pylibraft/pylibraft
            # test_doctests.py — docstring examples contain env-specific output
            # test_config.py  — uses bare pytest.skip() at module level (collection error)
            pytest --cache-clear -v \
                --ignore=tests/test_doctests.py \
                --ignore=tests/test_config.py \
                tests
        "
    echo ""
    echo "Python tests passed."
}

# ── main ───────────────────────────────────────────────────────────────────────
[[ ${DO_BUILD}  -eq 1 ]] && phase_build
[[ ${DO_SMOKE}  -eq 1 ]] && phase_smoke
[[ ${DO_TEST}   -eq 1 ]] && phase_test
[[ ${DO_PYTEST} -eq 1 ]] && phase_pytest

echo ""
echo "Done."
