#!/bin/bash
# raft_wheel_librmm_shared.sh — build librmm-cu13 + rmm-cu13 ONCE, shared
# across every GPU-architecture variant (gb10/rtx40xx/rtx50xx), and publish
# them to their own GitHub release.
#
# Why shared, not per-variant: librmm.so and rmm's compiled Cython
# extensions contain NO device code (confirmed via
# `cuobjdump --list-elf` -- "does not contain device code"), unlike
# libraft/pylibraft/raft-dask which genuinely differ per SM architecture.
# A single build is ABI-correct for every GPU variant; the only real axis
# here is the CUDA *toolkit* version (cu13.x), which is already captured
# in the distribution name/SONAME the same way upstream RAPIDS wheels do
# it. Building this separately from each raft_wheel_<variant>.sh avoids
# redundantly rebuilding an identical artifact three times.
#
# Distribution names are left PLAIN ("librmm-cu13"/"rmm-cu13", matching
# upstream) -- no "-<variant>" suffix, since there's no variant axis to
# distinguish. Only the VERSION differs from upstream's own nightly
# builds (this wheel is versioned to match whatever RMM commit raft's own
# CPM fetch actually resolved, not upstream's separate release cadence).
# This is safe as long as nothing else in the target environment hard-
# requires upstream's plain librmm/rmm at a conflicting version -- see
# raft_wheel_common.sh's validate_wheels() for the automated check that
# verifies this, and raft_wheel_rtx50xx.sh's raft-dask section for why
# ucxx (previously the one thing that did conflict) is excluded rather
# than accommodated.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=raft_wheel_common.sh
source "${PROJECT_ROOT}/raft_wheel_common.sh" || exit 1

# Any already-built variant's build dir works interchangeably as the
# source of RMM_SRC -- the CPM-fetched RMM commit is driven by
# rapids-cmake/the raft commit, not by GPU arch flags, so it does not
# vary across gb10/rtx40xx/rtx50xx. Override with e.g.
# `SOURCE_ARCH=gb10 bash raft_wheel_librmm_shared.sh` if rtx50xx hasn't
# been built on this machine.
SOURCE_ARCH="${SOURCE_ARCH:-rtx50xx}"
SOURCE_BUILD_DIR="${PROJECT_ROOT}/cpp/build-${SOURCE_ARCH}"
[[ -d "${SOURCE_BUILD_DIR}" ]] || {
    echo "ERROR: ${SOURCE_BUILD_DIR} not found -- build ${SOURCE_ARCH} first" \
         "(${SOURCE_ARCH}/raft_build_${SOURCE_ARCH}.sh) before running this script." >&2
    exit 1
}
RMM_SRC="${SOURCE_BUILD_DIR}/_deps/rmm-src"
[[ -d "${RMM_SRC}" ]] || { echo "ERROR: ${RMM_SRC} not found" >&2; exit 1; }

if ! command -v nvcc &>/dev/null; then
    mapfile -t _CUDA_TOOLKITS < <(for d in /usr/local/cuda-*; do [[ -x "${d}/bin/nvcc" ]] && echo "${d}"; done | sort -V)
    (( ${#_CUDA_TOOLKITS[@]} > 0 )) && export PATH="${_CUDA_TOOLKITS[-1]}/bin:${PATH}"
    unset _CUDA_TOOLKITS
fi
command -v nvcc &>/dev/null || { echo "ERROR: nvcc not found on PATH or under /usr/local/cuda-*" >&2; exit 1; }
CUDA_VERSION="$(nvcc --version | sed -n 's/.*release \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')"
CUDA_VERSION_COMPACT="${CUDA_VERSION//./}"
RMM_VERSION="$(cat "${RMM_SRC}/VERSION")"
RMM_SHORT_VER="$(echo "${RMM_VERSION}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"

DIST_DIR="${PROJECT_ROOT}/dist/shared"
WHEEL_SRC_RMM="${SOURCE_BUILD_DIR}/wheel-src-rmm-shared"
INSTALL_DIR="${SOURCE_BUILD_DIR}/install"
RELEASE_TAG="librmm-v${RMM_VERSION}-x86_64-cuda${CUDA_VERSION_COMPACT}"
RELEASE_TITLE="librmm/rmm ${RMM_VERSION} — x86_64 / CUDA ${CUDA_VERSION} (shared across all GPU variants)"
RELEASE_NOTES="${PROJECT_ROOT}/RELEASE_NOTES_librmm_${RMM_SHORT_VER}_shared.md"

echo "Installing build dependencies..."
pip install \
    --extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple \
    -r "${PROJECT_ROOT}/requirements-build-cuda13x.txt"

rm -rf "${DIST_DIR}" "${WHEEL_SRC_RMM}"
mkdir -p "${DIST_DIR}" "${WHEEL_SRC_RMM}"

stage_dependencies_yaml "${RMM_SRC}" "${WHEEL_SRC_RMM}"
stage_repo_root_refs "${RMM_SRC}" "${WHEEL_SRC_RMM}"

# ── librmm-cuXX (plain, no variant suffix) ────────────────────────────────
stage_package_source "${RMM_SRC}" "librmm" "${WHEEL_SRC_RMM}"
LIBRMM_STAGED="${WHEEL_SRC_RMM}/python/librmm"
LIBRMM_SONAME="librmm_cu${CUDA_VERSION_COMPACT}.so"

echo "Extracting librmm.so from existing cmake install (no recompile)..."
mkdir -p "${LIBRMM_STAGED}/librmm/lib64"
rm -rf /tmp/rmm-shared-install
cmake --install "${SOURCE_BUILD_DIR}" --prefix /tmp/rmm-shared-install
if [[ ! -f /tmp/rmm-shared-install/lib/librmm.so ]]; then
    echo "ERROR: cmake --install did not produce librmm.so" >&2
    exit 1
fi
cp /tmp/rmm-shared-install/lib/librmm.so "${LIBRMM_STAGED}/librmm/lib64/${LIBRMM_SONAME}"
rm -rf /tmp/rmm-shared-install
embed_build_info "${LIBRMM_STAGED}/librmm/lib64/${LIBRMM_SONAME}" "shared" "librmm" "${RMM_VERSION}+cu${CUDA_VERSION_COMPACT}"

# name/matrix-entry: only matrix-entry needs patching (enables the
# "-cu13" CUDA suffix rapids_build_backend appends) -- name stays the
# unpatched default "librmm" from source, no variant rename.
patch_line_or_fail "${LIBRMM_STAGED}/pyproject.toml" \
    '^matrix-entry = .*' 'matrix-entry = "cuda_suffixed=true;use_cuda_wheels=true"\ncommit-files = []' \
    "librmm matrix-entry"
echo "${RMM_VERSION}+cu${CUDA_VERSION_COMPACT}" > "${LIBRMM_STAGED}/librmm/VERSION"
patch_line_or_fail "${LIBRMM_STAGED}/librmm/load.py" \
    'soname = "librmm\.so"' "soname = \"${LIBRMM_SONAME}\"" "librmm load.py soname"

echo "Building librmm-cu13 wheel v${RMM_VERSION}+cu${CUDA_VERSION_COMPACT} for x86_64 (bundles librmm.so as ${LIBRMM_SONAME})..."
SKBUILD_CMAKE_ARGS="-DCMAKE_PREFIX_PATH=${INSTALL_DIR}" \
    pip wheel \
        --no-deps \
        --no-build-isolation \
        --wheel-dir "${DIST_DIR}" \
        "${LIBRMM_STAGED}"

LIBRMM_WHEEL="$(ls "${DIST_DIR}"/librmm*.whl 2>/dev/null | head -1)" || true
[[ -z "${LIBRMM_WHEEL}" ]] && { echo "ERROR: librmm wheel not found" >&2; exit 1; }
echo "librmm wheel: $(basename "${LIBRMM_WHEEL}") ($(du -sh "${LIBRMM_WHEEL}" | awk '{print $1}'))"

# ── rmm-cuXX (plain, no variant suffix) ───────────────────────────────────
# Real compile (Cython extensions), not an extract-a-prebuilt-.so step --
# see raft_wheel_rtx50xx.sh's earlier version of this comment (now
# removed from there) for the CMakeLists.txt reasoning.
stage_package_source "${RMM_SRC}" "rmm" "${WHEEL_SRC_RMM}"
RMM_STAGED="${WHEEL_SRC_RMM}/python/rmm"

patch_line_or_fail "${RMM_STAGED}/pyproject.toml" \
    '^matrix-entry = .*' 'matrix-entry = "cuda_suffixed=true"\ncommit-files = []' \
    "rmm matrix-entry"
echo "${RMM_VERSION}+cu${CUDA_VERSION_COMPACT}" > "${RMM_STAGED}/rmm/VERSION"
# rmm's own dependencies.yaml already correctly pins librmm==<RMM_SHORT_VER>.*
# (its own actual version) -- no patch needed here since we didn't rename
# librmm's distribution either.

echo "Building rmm-cu13 wheel v${RMM_VERSION}+cu${CUDA_VERSION_COMPACT} for x86_64..."
SKBUILD_CMAKE_ARGS="-DCMAKE_PREFIX_PATH=${INSTALL_DIR}" \
    pip wheel \
        --no-deps \
        --no-build-isolation \
        --wheel-dir "${DIST_DIR}" \
        "${RMM_STAGED}"

RMM_WHEEL="$(ls "${DIST_DIR}"/rmm_*.whl 2>/dev/null | head -1)" || true
[[ -z "${RMM_WHEEL}" ]] && { echo "ERROR: rmm wheel not found" >&2; exit 1; }
echo "rmm wheel: $(basename "${RMM_WHEEL}") ($(du -sh "${RMM_WHEEL}" | awk '{print $1}'))"

# ── Publish ────────────────────────────────────────────────────────────────
cd "${PROJECT_ROOT}"

RELEASE_NOTES_ARG=()
if [[ -f "${RELEASE_NOTES}" ]]; then
    RELEASE_NOTES_ARG=(--notes-file "${RELEASE_NOTES}")
else
    RELEASE_NOTES_ARG=(--notes "librmm-cu${CUDA_VERSION_COMPACT:0:2} + rmm-cu${CUDA_VERSION_COMPACT:0:2} ${RMM_VERSION}+cu${CUDA_VERSION_COMPACT} wheels for x86_64 / CUDA ${CUDA_VERSION}. No device code -- shared across every GPU-architecture variant (gb10/rtx40xx/rtx50xx); consumed by each variant's own libraft/pylibraft/raft-dask release.")
fi

echo "Publishing wheels to GitHub release ${RELEASE_TAG}..."
gh release create "${RELEASE_TAG}" \
    --repo zbrad/raft \
    --title "${RELEASE_TITLE}" \
    --target "native-builds" \
    "${RELEASE_NOTES_ARG[@]}" \
    "${LIBRMM_WHEEL}#$(basename "${LIBRMM_WHEEL}")" \
    "${RMM_WHEEL}#$(basename "${RMM_WHEEL}")"

echo ""
echo "Release: https://github.com/zbrad/raft/releases/tag/${RELEASE_TAG}"
echo "Done."
