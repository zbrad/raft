#!/bin/bash
# raft_wheel_gb10.sh — build libraft-gb10-cuXX + pylibraft-gb10-cuXX +
# raft-dask-gb10-cuXX wheels for GB10 / DGX Spark (SM_121a, aarch64) and
# package them for release, alongside copies of the shared librmm-cu13/
# rmm-cu13 wheels (built once by raft_wheel_librmm_shared.sh -- run that
# first).
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
# is untested against the shared-librmm/ucxx-exclusion design -- same
# mechanics, different hardware.
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
# RMM is fetched as a C++ build dependency of raft via rapids-cmake's CPM
# helper -- read here only to get its exact VERSION, so libraft/pylibraft/
# raft-dask's dependency pins below can be repointed at the matching
# version of the shared librmm-cu13/rmm-cu13 wheel (built once by
# raft_wheel_librmm_shared.sh, not rebuilt per variant -- see that script
# for why: librmm/rmm contain no device code, so a single build is
# ABI-correct for every GPU architecture).
RMM_SRC="${PROJECT_ROOT}/cpp/build-${ARCH}/_deps/rmm-src"
RMM_VERSION="$(cat "${RMM_SRC}/VERSION")"
RMM_SHORT_VER="$(echo "${RMM_VERSION}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"

# ── install build deps ─────────────────────────────────────────────────────────
echo "Installing build dependencies..."
pip install \
    --extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple \
    -r "${PROJECT_ROOT}/requirements-build-cuda13x.txt"

SHARED_DIST_DIR="${PROJECT_ROOT}/dist/shared"
[[ -n "$(ls "${SHARED_DIST_DIR}"/librmm*.whl 2>/dev/null)" && -n "$(ls "${SHARED_DIST_DIR}"/rmm_*.whl 2>/dev/null)" ]] || {
    echo "ERROR: ${SHARED_DIST_DIR} is missing librmm/rmm wheels -- run" \
         "raft_wheel_librmm_shared.sh first (librmm/rmm have no device code" \
         "and are built once, shared across all GPU variants, not per-variant)." >&2
    exit 1
}

rm -rf "${DIST_DIR}" "${WHEEL_SRC}"
mkdir -p "${DIST_DIR}" "${WHEEL_SRC}"
# Copy the pre-built, shared librmm/rmm wheels into this variant's own
# dist dir so a single `pip install dist/gb10/*.whl` and a single
# GitHub release still provide everything this variant needs -- the
# BUILD happens once (raft_wheel_librmm_shared.sh), but each variant's
# release still bundles copies for one-stop installability.
cp "${SHARED_DIST_DIR}"/librmm*.whl "${SHARED_DIST_DIR}"/rmm_*.whl "${DIST_DIR}/"
LIBRMM_WHEEL="$(ls "${DIST_DIR}"/librmm*.whl | head -1)"
RMM_WHEEL="$(ls "${DIST_DIR}"/rmm_*.whl | head -1)"
# Placed at the same relative depth from a staged package's pyproject.toml
# (wheel-src/python/<pkg>/) as the real dependencies.yaml is from the real
# one, so each package's existing `dependencies-file = "../../dependencies.yaml"`
# reference resolves correctly with no path rewriting.
stage_dependencies_yaml "${PROJECT_ROOT}" "${WHEEL_SRC}"
stage_repo_root_refs "${PROJECT_ROOT}" "${WHEEL_SRC}"
# libraft's OWN dependencies list (via depends_on_librmm) requires bare
# librmm-cu13 too -- this must be patched before ANY package is built
# against this staged dependencies.yaml, not just pylibraft/raft-dask's
# own cross-package dependency, or libraft-gb10-cu13's own metadata
# would still pull in the WRONG VERSION of librmm at install time
# (confirmed empirically on rtx50xx: this exact gap caused
# "undefined symbol: ...rmm::RMM_26_10::...pool_memory_resource_impl..."
# at runtime, since raft's C++ build fetches a newer RMM via CPM than
# dependencies.yaml's own "librmm==26.8.*" pin expects). Only the VERSION
# needs patching here, not the name -- librmm/rmm are built once, shared
# across every GPU variant (see raft_wheel_librmm_shared.sh; no per-arch
# device code means no per-variant distribution name is needed either).
patch_line_or_fail "${WHEEL_SRC}/dependencies.yaml" \
    "- librmm-cu${CUDA_VERSION_COMPACT:0:2}==26\.8\.\*,>=0\.0\.0a0" \
    "- librmm-cu${CUDA_VERSION_COMPACT:0:2}==${RMM_SHORT_VER}.*,>=0.0.0a0" \
    "libraft's librmm dependency (version -- our shared librmm-cu13 wheel is actually RMM's own ${RMM_VERSION}, not raft's 26.8.*)"
# pylibraft/raft-dask ALSO directly depend on bare "rmm==26.8.*" (the
# PYTHON rmm package, separate from librmm) -- same version mismatch,
# fixed the same way via raft_wheel_librmm_shared.sh's rmm-cu13 build.
patch_line_or_fail "${WHEEL_SRC}/dependencies.yaml" \
    "- rmm-cu${CUDA_VERSION_COMPACT:0:2}==26\.8\.\*,>=0\.0\.0a0" \
    "- rmm-cu${CUDA_VERSION_COMPACT:0:2}==${RMM_SHORT_VER}.*,>=0.0.0a0" \
    "pylibraft/raft-dask's rmm (python) dependency (version)"

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
embed_build_info "${LIBRAFT_STAGED}/libraft/lib64/${LIBRAFT_SONAME}" "gb10" "libraft" "${VERSION}+cu${CUDA_VERSION_COMPACT}"

patch_line_or_fail "${LIBRAFT_STAGED}/pyproject.toml" \
    '^name = "libraft"' 'name = "libraft-gb10"' "libraft package name"
patch_line_or_fail "${LIBRAFT_STAGED}/pyproject.toml" \
    '^matrix-entry = .*' 'matrix-entry = "cuda_suffixed=true;use_cuda_wheels=true"\ncommit-files = []' \
    "libraft matrix-entry"
echo "${VERSION}+cu${CUDA_VERSION_COMPACT}" > "${LIBRAFT_STAGED}/libraft/VERSION"
patch_line_or_fail "${LIBRAFT_STAGED}/libraft/load.py" \
    'soname = "libraft\.so"' "soname = \"${LIBRAFT_SONAME}\"" "libraft load.py soname"
# load.py's bare "import librmm" (preloading librmm.so before libraft.so
# itself, since libraft.so's symbols are a real runtime dependency of it)
# is left untouched -- matches upstream, no dynamic import_module() needed.
# See the PyTorch-ordering citation in raft_wheel_common.sh's
# validate_wheels() for why.

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
# Drop the hard dependency on distributed-ucxx-cu13 (UCX-based comms, an
# ALTERNATE backend to NCCL). Traced its C++ side (confirmed on rtx50xx,
# same source tree here): raft-dask's own CMakeLists.txt CPM-fetches+
# builds ucxx (get_ucxx.cmake) only to satisfy raft::distributed's
# exported CMake config at configure time -- the actual compiled
# extensions we ship (comms_utils.pyx/nccl.pyx, see
# raft_dask/common/CMakeLists.txt) link only against raft::raft/
# raft::distributed, never ucxx::ucxx/ucxx::python. So the CPM-built
# libucxx.a is unused build scaffolding, not something worth harvesting.
# The only REAL runtime use is the pure-Python raft_dask/common/ucx.py,
# an optional alternate transport this fork's actual use case (NCCL
# between GB10s) never touches. ucxx-cu13/libucxx-cu13 (upstream, not
# ours) hard-pin plain rmm-cu13/librmm-cu13==26.8.* in their own
# metadata -- installing them would reintroduce exactly the collision
# risk validate_wheels() detects, for a backend nothing here needs.
remove_yaml_include_or_fail "${WHEEL_SRC}/dependencies.yaml" "py_run_raft_dask" "depends_on_distributed_ucxx" \
    "drop hard ucxx dependency from raft-dask-gb10 (see ucx.py lazy-import patch below)"
# BUT raft-dask's compiled comms_utils.so (raft::distributed) has a real,
# unconditional DT_NEEDED on libucp.so.0 (raw UCX) regardless of whether
# the Python ucxx wrapper is used -- confirmed empirically on rtx50xx:
# removing distributed-ucxx above (which transitively supplied
# libucx-cu13) broke `import raft_dask` outright with "ImportError:
# libucp.so.0: cannot open shared object file". depends_on_ucx_build
# already declares the correct libucx-cu13 pin for pyproject/requirements
# output, but only for py_rapids_build_raft_dask (build-time); add it to
# py_run_raft_dask (runtime) too. Confirmed via PyPI metadata this has
# ZERO dependencies of its own (no rmm/librmm anywhere in its closure) --
# pure raw UCX, so this doesn't reopen the collision risk that ucxx did.
add_yaml_include_or_fail "${WHEEL_SRC}/dependencies.yaml" "py_run_raft_dask" "depends_on_ucx_build" \
    "add libucx-cu13 as a runtime (not just build-time) dependency of raft-dask-gb10"
# Move ucx.py's top-level "import ucxx" into UCX.__init__ so merely
# importing raft_dask (or using NCCL-based Comms, which never touches
# UCX) no longer requires ucxx to be installed at all -- only actually
# instantiating the UCX class does.
patch_line_or_fail "${RAFT_DASK_STAGED}/raft_dask/common/ucx.py" \
    '^import ucxx$' \
    '# ucxx is imported lazily in UCX.__init__ below -- not required just to import raft_dask' \
    "ucx.py lazy ucxx import (remove eager top-level import)"
insert_before_or_fail "${RAFT_DASK_STAGED}/raft_dask/common/ucx.py" \
    "        self.listener_callback = listener_callback" \
    "        global ucxx
        import ucxx
" \
    "ucx.py lazy ucxx import (import inside __init__)"
echo "${VERSION}+cu${CUDA_VERSION_COMPACT}" > "${RAFT_DASK_STAGED}/raft_dask/VERSION"
# Same dependencies.yaml-not-pyproject.toml reasoning as step 2 -- a
# second, different anchor line in the same staged copy (the libraft-cuXX==
# line patched in step 2 is still there; nothing reverts a generated file).
patch_line_or_fail "${WHEEL_SRC}/dependencies.yaml" \
    "- pylibraft-cu${CUDA_VERSION_COMPACT:0:2}==" "- pylibraft-gb10-cu${CUDA_VERSION_COMPACT:0:2}==" \
    "raft-dask's pylibraft dependency"

# raft-dask's build (CMake configure) needs find_package(ucx) at
# configure time. The pip libucx-cu13 wheel (installed via
# requirements-build-cuda13x.txt) does ship a CMake config
# (site-packages/libucx/lib/cmake/ucx/ucx-config.cmake), it's just not on
# CMake's default search path -- add it via the CMAKE_PREFIX_PATH
# *environment* variable (which CMake reads natively, unlike passing it
# through SKBUILD_CMAKE_ARGS's own semicolon-delimited arg list, which
# would collide with CMAKE_PREFIX_PATH's own semicolon-separated
# multi-path syntax).
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
# USE_NCCL_RUNTIME_WHEEL=ON (raft_dask/common/CMakeLists.txt, default OFF)
# sets the compiled extension's RPATH to $ORIGIN/../../nvidia/nccl/lib --
# i.e. the pip-installed nvidia-nccl-cu13 wheel's own bundled libnccl.so.2
# -- instead of expecting a system-wide NCCL install. Without this,
# `import raft_dask` fails with "ImportError: libnccl.so.2: cannot open
# shared object file" even though nvidia-nccl-cu13 IS installed (confirmed
# empirically on rtx50xx): the wheel is present, just not on the dynamic
# linker's default search path, and nothing set an RPATH to it at link time.
CMAKE_PREFIX_PATH="${INSTALL_DIR};${UCX_CMAKE_PREFIX}" \
SKBUILD_CMAKE_ARGS="-Draft_ROOT=${INSTALL_DIR};-DNCCL_LIBRARY=${NCCL_LIBRARY};-DNCCL_INCLUDE_DIR=${NCCL_PREFIX}/include;-DUSE_NCCL_RUNTIME_WHEEL=ON" \
    pip wheel \
        --no-deps \
        --no-build-isolation \
        --wheel-dir "${DIST_DIR}" \
        "${RAFT_DASK_STAGED}"

RAFT_DASK_WHEEL="$(ls "${DIST_DIR}"/raft_dask*.whl 2>/dev/null | head -1)" || true
[[ -z "${RAFT_DASK_WHEEL}" ]] && { echo "ERROR: raft-dask wheel not found" >&2; exit 1; }
echo "raft-dask wheel: $(basename "${RAFT_DASK_WHEEL}") ($(du -sh "${RAFT_DASK_WHEEL}" | awk '{print $1}'))"

# ── 4. Publish all five wheels ────────────────────────────────────────────────
# librmm-cu13/rmm-cu13 are copies of the shared build (raft_wheel_librmm_shared.sh
# published them under their own release already); bundled here too so this
# one release remains a complete, one-stop install for this GPU variant.
cd "${PROJECT_ROOT}"

RELEASE_NOTES_ARG=()
if [[ -f "${RELEASE_NOTES}" ]]; then
    RELEASE_NOTES_ARG=(--notes-file "${RELEASE_NOTES}")
else
    RELEASE_NOTES_ARG=(--notes "pylibraft-gb10-cu${CUDA_VERSION_COMPACT:0:2} + libraft-gb10-cu${CUDA_VERSION_COMPACT:0:2} + raft-dask-gb10-cu${CUDA_VERSION_COMPACT:0:2} ${VERSION}+cu${CUDA_VERSION_COMPACT} wheels for ${ARCH} / CUDA ${CUDA_VERSION} / SM_${GB10_CUDA_ARCH} (GB10 / DGX Spark), bundled with the shared librmm-cu13/rmm-cu13 $(basename "${LIBRMM_WHEEL}") build (no device code -- shared across GPU variants, see raft_wheel_librmm_shared.sh)")
fi

echo "Publishing wheels to GitHub release ${RELEASE_TAG}..."
gh release create "${RELEASE_TAG}" \
    --repo zbrad/raft \
    --title "${RELEASE_TITLE}" \
    --target "native-builds" \
    "${RELEASE_NOTES_ARG[@]}" \
    "${LIBRMM_WHEEL}#$(basename "${LIBRMM_WHEEL}")" \
    "${RMM_WHEEL}#$(basename "${RMM_WHEEL}")" \
    "${LIBRAFT_WHEEL}#$(basename "${LIBRAFT_WHEEL}")" \
    "${PYLIBRAFT_WHEEL}#$(basename "${PYLIBRAFT_WHEEL}")" \
    "${RAFT_DASK_WHEEL}#$(basename "${RAFT_DASK_WHEEL}")"

echo ""
echo "Release: https://github.com/zbrad/raft/releases/tag/${RELEASE_TAG}"
echo "Done."
