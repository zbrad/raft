#!/bin/bash
# raft_wheel_rtx50xx.sh — build libraft-rtx50xx-cuXX + pylibraft-rtx50xx-cuXX
# + raft-dask-rtx50xx-cuXX wheels for RTX 50xx (SM_120, x86_64) and package
# them for release.
#
# Each package is built from a per-variant staging copy under
# cpp/build-rtx50xx/wheel-src/ (see raft_wheel_common.sh) instead of
# patching the real python/<pkg>/ sources in place and reverting via a
# trap. The git-tracked tree is never modified, so there's nothing to
# revert and no risk of one package's build leaking into another's (the
# previous sed+trap approach hit exactly that: an EXIT trap set for one
# package silently replaces an earlier one instead of stacking).
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="rtx50xx"
# shellcheck source=raft_env_rtx50xx.sh
source "${PROJECT_ROOT}/rtx50xx/raft_env_rtx50xx.sh" || exit 1
# shellcheck source=../raft_wheel_common.sh
source "${PROJECT_ROOT}/raft_wheel_common.sh" || exit 1
INSTALL_DIR="${PROJECT_ROOT}/cpp/build-${ARCH}/install"
VERSION="$(cat "${PROJECT_ROOT}/VERSION")"
# Derive short version (e.g. 26.06.00 -> 26.6)
SHORT_VER="$(echo "${VERSION}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"
RELEASE_TAG="v${VERSION}-x86_64-cuda${CUDA_VERSION_COMPACT}-rtx50xx"
RELEASE_TITLE="RAFT ${SHORT_VER} — x86_64 / CUDA ${CUDA_VERSION} / SM_${RTX50_CUDA_ARCH} (RTX 50xx / Blackwell) wheels"
RELEASE_NOTES="${PROJECT_ROOT}/RELEASE_NOTES_${SHORT_VER}_rtx50xx.md"
DIST_DIR="${PROJECT_ROOT}/dist/rtx50xx"
WHEEL_SRC="${PROJECT_ROOT}/cpp/build-${ARCH}/wheel-src"

# ── install build deps ─────────────────────────────────────────────────────────
echo "Installing build dependencies..."
pip install \
    --extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple \
    -r "${PROJECT_ROOT}/requirements-build-cuda13x.txt"

rm -rf "${DIST_DIR}" "${WHEEL_SRC}"
mkdir -p "${DIST_DIR}" "${WHEEL_SRC}"
# Placed at the same relative depth from a staged package's pyproject.toml
# (wheel-src/python/<pkg>/) as the real dependencies.yaml is from the real
# one, so each package's existing `dependencies-file = "../../dependencies.yaml"`
# reference resolves correctly with no path rewriting.
stage_dependencies_yaml "${PROJECT_ROOT}" "${WHEEL_SRC}"
stage_repo_root_refs "${PROJECT_ROOT}" "${WHEEL_SRC}"

# ── 1. Build libraft-rtx50xx-cuXX ─────────────────────────────────────────────
# Strategy: pre-place libraft.so from the existing cmake install into the
# staged Python package directory (libraft/lib64/), same as before.
#
# Renamed to libraft-rtx50xx (was bare "libraft") so this RTX-50xx-only,
# sm_120-only build can never collide with upstream RAPIDS' real multi-arch
# libraft-cuXX wheel under the same name — same reasoning as gb10's rename,
# see gb10/raft_wheel_gb10.sh for the full rationale.
#
# The bundled .so is *also* renamed libraft.so -> libraft_rtx50xx_cuXXX.so
# (XXX = CUDA_VERSION_COMPACT) for the same collision-avoidance reason as
# gb10, safe for the same reason: dlopen() resolves by path, not filename,
# and the library still registers under its own unchanged SONAME
# ("libraft.so"), which is what pylibraft-rtx50xx's compiled extensions
# declare as NEEDED.
stage_package_source "${PROJECT_ROOT}" "libraft" "${WHEEL_SRC}"
LIBRAFT_STAGED="${WHEEL_SRC}/python/libraft"
LIBRAFT_SONAME="libraft_rtx50xx_cu${CUDA_VERSION_COMPACT}.so"

echo "Extracting libraft.so from existing cmake install (no recompile)..."
mkdir -p "${LIBRAFT_STAGED}/libraft/lib64"
rm -rf /tmp/raft-rtx50xx-install
cmake --install "${PROJECT_ROOT}/cpp/build-${ARCH}" --prefix /tmp/raft-rtx50xx-install
if [[ ! -f /tmp/raft-rtx50xx-install/lib/libraft.so ]]; then
    echo "ERROR: cmake --install did not produce libraft.so" >&2
    exit 1
fi
verify_rtx50xx_arch /tmp/raft-rtx50xx-install/lib/libraft.so || exit 1
cp /tmp/raft-rtx50xx-install/lib/libraft.so "${LIBRAFT_STAGED}/libraft/lib64/${LIBRAFT_SONAME}"
rm -rf /tmp/raft-rtx50xx-install

patch_line_or_fail "${LIBRAFT_STAGED}/pyproject.toml" \
    '^name = "libraft"' 'name = "libraft-rtx50xx"' "libraft package name"
patch_line_or_fail "${LIBRAFT_STAGED}/pyproject.toml" \
    '^matrix-entry = .*' 'matrix-entry = "cuda_suffixed=true;use_cuda_wheels=true"\ncommit-files = []' \
    "libraft matrix-entry"
echo "${VERSION}+cu${CUDA_VERSION_COMPACT}" > "${LIBRAFT_STAGED}/libraft/VERSION"
patch_line_or_fail "${LIBRAFT_STAGED}/libraft/load.py" \
    'soname = "libraft\.so"' "soname = \"${LIBRAFT_SONAME}\"" "libraft load.py soname"

echo "Building libraft-rtx50xx wheel v${VERSION}+cu${CUDA_VERSION_COMPACT} for x86_64 (bundles libraft.so as ${LIBRAFT_SONAME})..."
SKBUILD_CMAKE_ARGS="-DCMAKE_PREFIX_PATH=${INSTALL_DIR}" \
    pip wheel \
        --no-deps \
        --no-build-isolation \
        --wheel-dir "${DIST_DIR}" \
        "${LIBRAFT_STAGED}"

LIBRAFT_WHEEL="$(ls "${DIST_DIR}"/libraft*.whl 2>/dev/null | head -1)" || true
[[ -z "${LIBRAFT_WHEEL}" ]] && { echo "ERROR: libraft wheel not found" >&2; exit 1; }
echo "libraft wheel: $(basename "${LIBRAFT_WHEEL}") ($(du -sh "${LIBRAFT_WHEEL}" | awk '{print $1}'))"

# ── 2. Build pylibraft-rtx50xx-cuXX ───────────────────────────────────────────
stage_package_source "${PROJECT_ROOT}" "pylibraft" "${WHEEL_SRC}"
PYLIBRAFT_STAGED="${WHEEL_SRC}/python/pylibraft"

patch_line_or_fail "${PYLIBRAFT_STAGED}/pyproject.toml" \
    '^name = "pylibraft"' 'name = "pylibraft-rtx50xx"' "pylibraft package name"
patch_line_or_fail "${PYLIBRAFT_STAGED}/pyproject.toml" \
    '^matrix-entry = .*' 'matrix-entry = "cuda_suffixed=true"\ncommit-files = []' \
    "pylibraft matrix-entry"
echo "${VERSION}+cu${CUDA_VERSION_COMPACT}" > "${PYLIBRAFT_STAGED}/pylibraft/VERSION"
# Editing pylibraft's own "libraft==" line in pyproject.toml directly does
# NOT work -- rapids_build_backend regenerates the dependencies list from
# dependencies.yaml at build time and silently overwrites any hand-edit
# there (verified empirically in earlier work on this pipeline: a
# pyproject.toml-only edit left Requires-Dist pointing at the un-renamed
# "libraft-cu13"). The fix has to go in the staged dependencies.yaml copy.
patch_line_or_fail "${WHEEL_SRC}/dependencies.yaml" \
    "- libraft-cu${CUDA_VERSION_COMPACT:0:2}==" "- libraft-rtx50xx-cu${CUDA_VERSION_COMPACT:0:2}==" \
    "pylibraft's libraft dependency"

echo "Building pylibraft-rtx50xx wheel v${VERSION}+cu${CUDA_VERSION_COMPACT} for x86_64 (SM_${RTX50_CUDA_ARCH} only)..."
SKBUILD_CMAKE_ARGS="-Draft_ROOT=${INSTALL_DIR};-DCMAKE_PREFIX_PATH=${INSTALL_DIR};-DCMAKE_CUDA_ARCHITECTURES=${RTX50_CUDA_ARCH}" \
    pip wheel \
        --no-deps \
        --no-build-isolation \
        --wheel-dir "${DIST_DIR}" \
        "${PYLIBRAFT_STAGED}"

PYLIBRAFT_WHEEL="$(ls "${DIST_DIR}"/pylibraft*.whl 2>/dev/null | head -1)" || true
[[ -z "${PYLIBRAFT_WHEEL}" ]] && { echo "ERROR: pylibraft wheel not found" >&2; exit 1; }
echo "pylibraft wheel: $(basename "${PYLIBRAFT_WHEEL}") ($(du -sh "${PYLIBRAFT_WHEEL}" | awk '{print $1}'))"

# ── 3. Build raft-dask-rtx50xx-cuXX ───────────────────────────────────────────
# raft-dask is the distributed multi-GPU/multi-node comms layer (NCCL/UCX)
# built on top of libraft/pylibraft — needed for multi-node NCCL-connected
# setups (e.g. multiple GB10s bridged together), not single-node usage.
# Its Cython extensions (comms_utils.pyx, nccl.pyx) link against
# raft::raft/raft::distributed as CXX (host) code, not device kernels, so
# no CMAKE_CUDA_ARCHITECTURES pin is needed here, unlike pylibraft above.
stage_package_source "${PROJECT_ROOT}" "raft-dask" "${WHEEL_SRC}"
RAFT_DASK_STAGED="${WHEEL_SRC}/python/raft-dask"

patch_line_or_fail "${RAFT_DASK_STAGED}/pyproject.toml" \
    '^name = "raft-dask"' 'name = "raft-dask-rtx50xx"' "raft-dask package name"
patch_line_or_fail "${RAFT_DASK_STAGED}/pyproject.toml" \
    '^matrix-entry = .*' 'matrix-entry = "cuda_suffixed=true"\ncommit-files = []' \
    "raft-dask matrix-entry"
echo "${VERSION}+cu${CUDA_VERSION_COMPACT}" > "${RAFT_DASK_STAGED}/raft_dask/VERSION"
# Same dependencies.yaml-not-pyproject.toml reasoning as step 2 -- a
# second, different anchor line in the same staged copy (the libraft-cuXX==
# line patched in step 2 is still there; nothing reverts a generated file).
patch_line_or_fail "${WHEEL_SRC}/dependencies.yaml" \
    "- pylibraft-cu${CUDA_VERSION_COMPACT:0:2}==" "- pylibraft-rtx50xx-cu${CUDA_VERSION_COMPACT:0:2}==" \
    "raft-dask's pylibraft dependency"

# raft-dask's dependency ucxx needs find_package(ucx) at CMake configure
# time. The pip libucx-cu13 wheel (installed via requirements-build-cuda13x.txt)
# does ship a CMake config (site-packages/libucx/lib/cmake/ucx/ucx-config.cmake),
# it's just not on CMake's default search path -- add it via the
# CMAKE_PREFIX_PATH *environment* variable (which CMake reads natively,
# unlike passing it through SKBUILD_CMAKE_ARGS's own semicolon-delimited
# arg list, which would collide with CMAKE_PREFIX_PATH's own semicolon-
# separated multi-path syntax).
UCX_CMAKE_PREFIX="$(python3 -c 'import libucx, os; print(os.path.dirname(libucx.__file__))')"
# raft's own FindNCCL.cmake (raft-config.cmake -> raft-distributed-dependencies.cmake)
# falls back to find_library(NAMES nccl) / find_path(NAMES nccl.h) when no
# NCCL config-package is found (there isn't one from a pip install). The
# nvidia-nccl-cu13 wheel only ships a versioned libnccl.so.2 -- no
# unversioned libnccl.so symlink find_library's default name search
# expects -- so point NCCL_LIBRARY/NCCL_INCLUDE_DIR at the exact wheel
# paths directly rather than fighting find_library's naming assumptions.
# Note: nvidia.nccl is a namespace package (no __init__.py) -- __file__ is
# None on it, use __path__ instead.
NCCL_PREFIX="$(python3 -c 'import nvidia.nccl as m; print(list(m.__path__)[0])')"
NCCL_LIBRARY="$(ls "${NCCL_PREFIX}"/lib/libnccl.so* | head -1)"

echo "Building raft-dask-rtx50xx wheel v${VERSION}+cu${CUDA_VERSION_COMPACT} for x86_64..."
CMAKE_PREFIX_PATH="${INSTALL_DIR};${UCX_CMAKE_PREFIX}" \
SKBUILD_CMAKE_ARGS="-Draft_ROOT=${INSTALL_DIR};-DNCCL_LIBRARY=${NCCL_LIBRARY};-DNCCL_INCLUDE_DIR=${NCCL_PREFIX}/include" \
    pip wheel \
        --no-deps \
        --no-build-isolation \
        --wheel-dir "${DIST_DIR}" \
        "${RAFT_DASK_STAGED}"

RAFT_DASK_WHEEL="$(ls "${DIST_DIR}"/raft_dask*.whl 2>/dev/null | head -1)" || true
[[ -z "${RAFT_DASK_WHEEL}" ]] && { echo "ERROR: raft-dask wheel not found" >&2; exit 1; }
echo "raft-dask wheel: $(basename "${RAFT_DASK_WHEEL}") ($(du -sh "${RAFT_DASK_WHEEL}" | awk '{print $1}'))"

# ── 4. Publish all three wheels ───────────────────────────────────────────────
cd "${PROJECT_ROOT}"

RELEASE_NOTES_ARG=()
if [[ -f "${RELEASE_NOTES}" ]]; then
    RELEASE_NOTES_ARG=(--notes-file "${RELEASE_NOTES}")
else
    RELEASE_NOTES_ARG=(--notes "pylibraft-rtx50xx-cu${CUDA_VERSION_COMPACT:0:2} + libraft-rtx50xx-cu${CUDA_VERSION_COMPACT:0:2} + raft-dask-rtx50xx-cu${CUDA_VERSION_COMPACT:0:2} ${VERSION}+cu${CUDA_VERSION_COMPACT} wheels for x86_64 / CUDA ${CUDA_VERSION} / SM_${RTX50_CUDA_ARCH} (RTX 50xx / Blackwell)")
fi

echo "Publishing wheels to GitHub release ${RELEASE_TAG}..."
gh release create "${RELEASE_TAG}" \
    --repo zbrad/raft \
    --title "${RELEASE_TITLE}" \
    --target "native-builds" \
    "${RELEASE_NOTES_ARG[@]}" \
    "${LIBRAFT_WHEEL}#$(basename "${LIBRAFT_WHEEL}")" \
    "${PYLIBRAFT_WHEEL}#$(basename "${PYLIBRAFT_WHEEL}")" \
    "${RAFT_DASK_WHEEL}#$(basename "${RAFT_DASK_WHEEL}")"

echo ""
echo "Release: https://github.com/zbrad/raft/releases/tag/${RELEASE_TAG}"
echo "Done."
