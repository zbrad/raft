#!/bin/bash
# raft_wheel_gb10.sh — build libraft-gb10-cuXX + pylibraft-gb10-cuXX +
# raft-dask-gb10-cuXX wheels for GB10 / DGX Spark (SM_121a, aarch64) and
# package them for release.
#
# Each package is built from a per-variant staging copy under
# cpp/build-<arch>/wheel-src/ (see raft_wheel_common.sh) instead of
# patching the real python/<pkg>/ sources in place and reverting via a
# trap. The git-tracked tree is never modified, so there's nothing to
# revert and no risk of one package's build leaking into another's (the
# previous sed+trap approach hit exactly that: an EXIT trap set for one
# package silently replaces an earlier one instead of stacking).
#
# NOTE: mirrors rtx50xx/raft_wheel_rtx50xx.sh, which is fully verified
# end-to-end on real hardware. This variant (gb10 specifically, aarch64)
# is untested against the new staging design — same mechanics, different
# hardware.
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="$(uname -m)"
# shellcheck source=raft_env_gb10.sh
source "${PROJECT_ROOT}/gb10/raft_env_gb10.sh" || exit 1
# shellcheck source=../raft_wheel_common.sh
source "${PROJECT_ROOT}/raft_wheel_common.sh" || exit 1
INSTALL_DIR="${PROJECT_ROOT}/cpp/build-${ARCH}/install"
VERSION="$(cat "${PROJECT_ROOT}/VERSION")"
# Derive short version (e.g. 26.06.00 -> 26.6)
SHORT_VER="$(echo "${VERSION}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"
RELEASE_TAG="v${VERSION}-${ARCH}-cuda${CUDA_VERSION_COMPACT}-gb10"
RELEASE_TITLE="RAFT ${SHORT_VER} — ${ARCH} / CUDA ${CUDA_VERSION} / SM_${GB10_CUDA_ARCH} (GB10 / DGX Spark) wheels"
RELEASE_NOTES="${PROJECT_ROOT}/RELEASE_NOTES_${SHORT_VER}_gb10_cu${CUDA_VERSION_COMPACT}.md"
DIST_DIR="${PROJECT_ROOT}/dist/gb10"
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

# ── 1. Build libraft-gb10-cuXX ─────────────────────────────────────────────────
# Strategy: pre-place libraft.so from the existing cmake install into the
# staged Python package directory (libraft/lib64/), same as before.
#
# Renamed to libraft-gb10 (was bare "libraft") so this GB10-only,
# sm_121a-only build can never collide with upstream RAPIDS' real
# multi-arch libraft-cuXX wheel under the same name. cuda_suffixed's
# auto-appended "-cu13" (major-only -- rapids_build_backend hardcodes
# major-version-only suffixing, see rapids_build_backend/impls.py:_get_cuda_suffix)
# is left alone rather than fought, since disabling it (disable-cuda=true)
# was verified to also corrupt this package's own Requires-Dist entries
# (drops the "-cu13" reference entirely). The exact CUDA minor version
# instead goes into the wheel's own VERSION as a "+cuXX" local segment.
#
# The bundled .so is *also* renamed libraft.so -> libraft_gb10_cuXXX.so
# (XXX = CUDA_VERSION_COMPACT) for the same collision-avoidance reason,
# safe for the same reason: dlopen() resolves by path, not filename, and
# the library still registers under its own unchanged SONAME
# ("libraft.so"), which is what pylibraft-gb10's compiled extensions
# declare as NEEDED.
stage_package_source "${PROJECT_ROOT}" "libraft" "${WHEEL_SRC}"
LIBRAFT_STAGED="${WHEEL_SRC}/python/libraft"
LIBRAFT_SONAME="libraft_gb10_cu${CUDA_VERSION_COMPACT}.so"

echo "Extracting libraft.so from existing cmake install (no recompile)..."
mkdir -p "${LIBRAFT_STAGED}/libraft/lib64"
rm -rf /tmp/raft-gb10-install
cmake --install "${PROJECT_ROOT}/cpp/build-${ARCH}" --prefix /tmp/raft-gb10-install
if [[ ! -f /tmp/raft-gb10-install/lib/libraft.so ]]; then
    echo "ERROR: cmake --install did not produce libraft.so" >&2
    exit 1
fi
verify_gb10_arch /tmp/raft-gb10-install/lib/libraft.so || exit 1
cp /tmp/raft-gb10-install/lib/libraft.so "${LIBRAFT_STAGED}/libraft/lib64/${LIBRAFT_SONAME}"
rm -rf /tmp/raft-gb10-install

patch_line_or_fail "${LIBRAFT_STAGED}/pyproject.toml" \
    '^name = "libraft"' 'name = "libraft-gb10"' "libraft package name"
patch_line_or_fail "${LIBRAFT_STAGED}/pyproject.toml" \
    '^matrix-entry = .*' 'matrix-entry = "cuda_suffixed=true;use_cuda_wheels=true"\ncommit-files = []' \
    "libraft matrix-entry"
echo "${VERSION}+cu${CUDA_VERSION_COMPACT}" > "${LIBRAFT_STAGED}/libraft/VERSION"
patch_line_or_fail "${LIBRAFT_STAGED}/libraft/load.py" \
    'soname = "libraft\.so"' "soname = \"${LIBRAFT_SONAME}\"" "libraft load.py soname"

echo "Building libraft-gb10 wheel v${VERSION}+cu${CUDA_VERSION_COMPACT} for ${ARCH} (bundles libraft.so as ${LIBRAFT_SONAME})..."
SKBUILD_CMAKE_ARGS="-DCMAKE_PREFIX_PATH=${INSTALL_DIR}" \
    pip wheel \
        --no-deps \
        --no-build-isolation \
        --wheel-dir "${DIST_DIR}" \
        "${LIBRAFT_STAGED}"

LIBRAFT_WHEEL="$(ls "${DIST_DIR}"/libraft*.whl 2>/dev/null | head -1)" || true
[[ -z "${LIBRAFT_WHEEL}" ]] && { echo "ERROR: libraft wheel not found" >&2; exit 1; }
echo "libraft wheel: $(basename "${LIBRAFT_WHEEL}") ($(du -sh "${LIBRAFT_WHEEL}" | awk '{print $1}'))"

# ── 2. Build pylibraft-gb10-cuXX ──────────────────────────────────────────────
stage_package_source "${PROJECT_ROOT}" "pylibraft" "${WHEEL_SRC}"
PYLIBRAFT_STAGED="${WHEEL_SRC}/python/pylibraft"

patch_line_or_fail "${PYLIBRAFT_STAGED}/pyproject.toml" \
    '^name = "pylibraft"' 'name = "pylibraft-gb10"' "pylibraft package name"
patch_line_or_fail "${PYLIBRAFT_STAGED}/pyproject.toml" \
    '^matrix-entry = .*' 'matrix-entry = "cuda_suffixed=true"\ncommit-files = []' \
    "pylibraft matrix-entry"
echo "${VERSION}+cu${CUDA_VERSION_COMPACT}" > "${PYLIBRAFT_STAGED}/pylibraft/VERSION"
# Editing pylibraft's own "libraft==" line in pyproject.toml directly does
# NOT work -- rapids_build_backend regenerates the dependencies list from
# dependencies.yaml at build time and silently overwrites any hand-edit
# there (verified empirically: a pyproject.toml-only edit left
# Requires-Dist pointing at the un-renamed "libraft-cu13"). The fix has
# to go in the staged dependencies.yaml copy.
patch_line_or_fail "${WHEEL_SRC}/dependencies.yaml" \
    "- libraft-cu${CUDA_VERSION_COMPACT:0:2}==" "- libraft-gb10-cu${CUDA_VERSION_COMPACT:0:2}==" \
    "pylibraft's libraft dependency"

echo "Building pylibraft-gb10 wheel v${VERSION}+cu${CUDA_VERSION_COMPACT} for ${ARCH} (SM_${GB10_CUDA_ARCH} only)..."
SKBUILD_CMAKE_ARGS="-Draft_ROOT=${INSTALL_DIR};-DCMAKE_PREFIX_PATH=${INSTALL_DIR};-DCMAKE_CUDA_ARCHITECTURES=${GB10_CUDA_ARCH}" \
    pip wheel \
        --no-deps \
        --no-build-isolation \
        --wheel-dir "${DIST_DIR}" \
        "${PYLIBRAFT_STAGED}"

PYLIBRAFT_WHEEL="$(ls "${DIST_DIR}"/pylibraft*.whl 2>/dev/null | head -1)" || true
[[ -z "${PYLIBRAFT_WHEEL}" ]] && { echo "ERROR: pylibraft wheel not found" >&2; exit 1; }
echo "pylibraft wheel: $(basename "${PYLIBRAFT_WHEEL}") ($(du -sh "${PYLIBRAFT_WHEEL}" | awk '{print $1}'))"

# ── 3. Build raft-dask-gb10-cuXX ──────────────────────────────────────────────
# raft-dask is the distributed multi-GPU/multi-node comms layer (NCCL/UCX)
# built on top of libraft/pylibraft — needed for multi-node NCCL-connected
# setups (e.g. multiple GB10s bridged together), not single-node usage.
# Its Cython extensions (comms_utils.pyx, nccl.pyx) link against
# raft::raft/raft::distributed as CXX (host) code, not device kernels, so
# no CMAKE_CUDA_ARCHITECTURES pin is needed here, unlike pylibraft above.
stage_package_source "${PROJECT_ROOT}" "raft-dask" "${WHEEL_SRC}"
RAFT_DASK_STAGED="${WHEEL_SRC}/python/raft-dask"

patch_line_or_fail "${RAFT_DASK_STAGED}/pyproject.toml" \
    '^name = "raft-dask"' 'name = "raft-dask-gb10"' "raft-dask package name"
patch_line_or_fail "${RAFT_DASK_STAGED}/pyproject.toml" \
    '^matrix-entry = .*' 'matrix-entry = "cuda_suffixed=true"\ncommit-files = []' \
    "raft-dask matrix-entry"
echo "${VERSION}+cu${CUDA_VERSION_COMPACT}" > "${RAFT_DASK_STAGED}/raft_dask/VERSION"
# Same dependencies.yaml-not-pyproject.toml reasoning as step 2 -- a
# second, different anchor line in the same staged copy (the libraft-cuXX==
# line patched in step 2 is still there; nothing reverts a generated file).
patch_line_or_fail "${WHEEL_SRC}/dependencies.yaml" \
    "- pylibraft-cu${CUDA_VERSION_COMPACT:0:2}==" "- pylibraft-gb10-cu${CUDA_VERSION_COMPACT:0:2}==" \
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

echo "Building raft-dask-gb10 wheel v${VERSION}+cu${CUDA_VERSION_COMPACT} for ${ARCH}..."
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
    RELEASE_NOTES_ARG=(--notes "pylibraft-gb10-cu${CUDA_VERSION_COMPACT:0:2} + libraft-gb10-cu${CUDA_VERSION_COMPACT:0:2} + raft-dask-gb10-cu${CUDA_VERSION_COMPACT:0:2} ${VERSION}+cu${CUDA_VERSION_COMPACT} wheels for ${ARCH} / CUDA ${CUDA_VERSION} / SM_${GB10_CUDA_ARCH} (GB10 / DGX Spark)")
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
