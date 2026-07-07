#!/bin/bash
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="$(uname -m)"
# shellcheck source=raft_env_gb10.sh
source "${PROJECT_ROOT}/gb10/raft_env_gb10.sh" || exit 1
INSTALL_DIR="${PROJECT_ROOT}/cpp/build-${ARCH}/install"
VERSION="$(cat "${PROJECT_ROOT}/VERSION")"
# Derive short version (e.g. 26.06.00 -> 26.6)
SHORT_VER="$(echo "${VERSION}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"
RELEASE_TAG="v${VERSION}-${ARCH}-cuda${CUDA_VERSION_COMPACT}-gb10"
RELEASE_TITLE="RAFT ${SHORT_VER} — ${ARCH} / CUDA ${CUDA_VERSION} / SM_${GB10_CUDA_ARCH} (GB10 / DGX Spark) wheels"
RELEASE_NOTES="${PROJECT_ROOT}/RELEASE_NOTES_${SHORT_VER}_${ARCH}.md"
DIST_DIR="${PROJECT_ROOT}/dist/gb10"

# ── helpers ────────────────────────────────────────────────────────────────────

# ── install build deps ─────────────────────────────────────────────────────────
echo "Installing build dependencies..."
pip install \
    --extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple \
    -r "${PROJECT_ROOT}/requirements-build-cuda132.txt"

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

# ── 1. Build libraft-gb10-cuXX ────────────────────────────────────────────────
# Strategy: pre-place libraft.so from the existing cmake install into the Python
# package directory (libraft/lib64/).  scikit-build-core includes all files from
# wheel.packages, so the .so gets bundled.  Setting CMAKE_PREFIX_PATH makes
# find_package(raft) succeed and return early — no C++ recompilation needed.
#
# Renamed to libraft-gb10 (was bare "libraft") so this GB10-only, sm_121a-only
# build can never collide with upstream RAPIDS' real multi-arch libraft-cuXX
# wheel under the same name. cuda_suffixed's auto-appended "-cu13" (major-only
# -- rapids_build_backend hardcodes major-version-only suffixing, see
# rapids_build_backend/impls.py:_get_cuda_suffix) is left alone rather than
# fought, since disabling it (disable-cuda=true) was verified to also corrupt
# this package's own Requires-Dist entries (drops the "-cu13" reference
# entirely). The exact CUDA minor version instead goes into the wheel's own
# VERSION as a "+cuXX" local segment, mirroring how pytorch's GB10 build keeps
# "torch" as the package name and puts ".cu133" in the version string instead.
#
# The bundled .so is *also* renamed libraft.so -> libraft_gb10_cuXXX.so (XXX =
# CUDA_VERSION_COMPACT), since both this wheel and upstream's real
# libraft-cuXX wheel install into the same "libraft" import package (only the
# PyPI distribution name differs) -- if both ever end up installed side by
# side, unrenamed same-named .so files would silently clobber one another on
# disk. Folding in the CUDA minor version too keeps the on-disk name as
# self-describing as the wheel version string. This is safe without touching
# the file's embedded SONAME or any consumer's NEEDED entries: dlopen() cares
# about the path it's given, not the filename, and once loaded the library is
# registered under its own SONAME (still "libraft.so") -- which is exactly
# what pylibraft-gb10's compiled extensions declare as NEEDED, so they still
# resolve against it.
LIBRAFT_PYPROJECT="${PROJECT_ROOT}/python/libraft/pyproject.toml"
LIBRAFT_LOAD_PY="${PROJECT_ROOT}/python/libraft/libraft/load.py"
LIBRAFT_LIB64="${PROJECT_ROOT}/python/libraft/libraft/lib64"
LIBRAFT_SONAME="libraft_gb10_cu${CUDA_VERSION_COMPACT}.so"
# VERSION is a symlink to the shared repo-root VERSION file -- resolve it
# first so sed -i edits the real target instead of clobbering the symlink
# with a regular file (bit us during testing: git showed the symlink turned
# into a plain file after a naive sed -i on the link path).
LIBRAFT_VERSION_FILE="$(readlink -f "${PROJECT_ROOT}/python/libraft/libraft/VERSION")"

echo "Extracting libraft.so from existing cmake install (no recompile)..."
mkdir -p "${LIBRAFT_LIB64}"
rm -rf /tmp/raft-gb10-install
cmake --install "${PROJECT_ROOT}/cpp/build-${ARCH}" --prefix /tmp/raft-gb10-install
if [[ ! -f /tmp/raft-gb10-install/lib/libraft.so ]]; then
    echo "ERROR: cmake --install did not produce libraft.so" >&2
    exit 1
fi
verify_gb10_arch /tmp/raft-gb10-install/lib/libraft.so || exit 1
cp /tmp/raft-gb10-install/lib/libraft.so "${LIBRAFT_LIB64}/${LIBRAFT_SONAME}"
rm -rf /tmp/raft-gb10-install

# Patch: rename to libraft-gb10, embed CUDA minor version in VERSION, point
# load.py at the renamed libraft_gb10_cuXXX.so, disable GIT_COMMIT path lookup
sed -i \
    -e "s/^name = \"libraft\"/name = \"libraft-gb10\"/" \
    -e "s/^matrix-entry = .*/matrix-entry = \"cuda_suffixed=true;use_cuda_wheels=true\"\ncommit-files = []/" \
    "${LIBRAFT_PYPROJECT}"
sed -i "s/\$/+cu${CUDA_VERSION_COMPACT}/" "${LIBRAFT_VERSION_FILE}"
sed -i "s/soname = \"libraft\.so\"/soname = \"${LIBRAFT_SONAME}\"/" "${LIBRAFT_LOAD_PY}"
trap 'sed -i \
    -e "s/^name = \"libraft-gb10\"/name = \"libraft\"/" \
    -e "/^commit-files = \[\]/d" \
    "${LIBRAFT_PYPROJECT}"
     sed -i "s/+cu${CUDA_VERSION_COMPACT}\$//" "${LIBRAFT_VERSION_FILE}"
     sed -i "s/soname = \"libraft_gb10_cu[0-9]*\.so\"/soname = \"libraft.so\"/" "${LIBRAFT_LOAD_PY}"
     rm -rf "${LIBRAFT_LIB64}"' EXIT

echo "Building libraft-gb10 wheel v${VERSION}+cu${CUDA_VERSION_COMPACT} for ${ARCH} (bundles libraft.so as ${LIBRAFT_SONAME})..."
SKBUILD_CMAKE_ARGS="-DCMAKE_PREFIX_PATH=${INSTALL_DIR}" \
    pip wheel \
        --no-deps \
        --no-build-isolation \
        --wheel-dir "${DIST_DIR}" \
        "${PROJECT_ROOT}/python/libraft"

LIBRAFT_WHEEL="$(ls "${DIST_DIR}"/libraft*.whl 2>/dev/null | head -1)" || true
[[ -z "${LIBRAFT_WHEEL}" ]] && { echo "ERROR: libraft wheel not found" >&2; exit 1; }
echo "libraft wheel: $(basename "${LIBRAFT_WHEEL}") ($(du -sh "${LIBRAFT_WHEEL}" | awk '{print $1}'))"

# Restore libraft pyproject.toml, VERSION, load.py, and lib64 before pylibraft build
sed -i \
    -e "s/^name = \"libraft-gb10\"/name = \"libraft\"/" \
    -e "/^commit-files = \[\]/d" \
    "${LIBRAFT_PYPROJECT}"
sed -i "s/+cu${CUDA_VERSION_COMPACT}\$//" "${LIBRAFT_VERSION_FILE}"
sed -i "s/soname = \"libraft_gb10_cu[0-9]*\.so\"/soname = \"libraft.so\"/" "${LIBRAFT_LOAD_PY}"
rm -rf "${LIBRAFT_LIB64}"
trap - EXIT

# ── 2. Build pylibraft-gb10-cuXX ──────────────────────────────────────────────
PYLIBRAFT_PYPROJECT="${PROJECT_ROOT}/python/pylibraft/pyproject.toml"
PYLIBRAFT_VERSION_FILE="$(readlink -f "${PROJECT_ROOT}/python/pylibraft/pylibraft/VERSION")"
DEPENDENCIES_YAML="${PROJECT_ROOT}/dependencies.yaml"

# Patch: rename to pylibraft-gb10, embed CUDA minor version in VERSION,
# disable GIT_COMMIT path lookup. Editing pylibraft's own "libraft==" line in
# pyproject.toml directly does NOT work -- rapids_build_backend regenerates
# the dependencies list from dependencies.yaml at build time (via
# make_dependency_files()) and silently overwrites any hand-edit there, so
# the actual fix has to go in dependencies.yaml's depends_on_libraft set
# instead (verified empirically: a pyproject.toml-only edit left
# Requires-Dist pointing at the un-renamed "libraft-cu13").
sed -i \
    -e "s/^name = \"pylibraft\"/name = \"pylibraft-gb10\"/" \
    -e "s/^matrix-entry = .*/matrix-entry = \"cuda_suffixed=true\"\ncommit-files = []/" \
    "${PYLIBRAFT_PYPROJECT}"
sed -i "s/\$/+cu${CUDA_VERSION_COMPACT}/" "${PYLIBRAFT_VERSION_FILE}"
# The "- libraft-cuXX==" prefix (dash-space) disambiguates from the
# "- pylibraft-cuXX==" line just above it in the same file, which contains
# "libraft-cuXX==" as a substring.
sed -i "s/- libraft-cu${CUDA_VERSION_COMPACT:0:2}==/- libraft-gb10-cu${CUDA_VERSION_COMPACT:0:2}==/" "${DEPENDENCIES_YAML}"
trap 'sed -i \
    -e "s/^name = \"pylibraft-gb10\"/name = \"pylibraft\"/" \
    -e "/^commit-files = \[\]/d" \
    "${PYLIBRAFT_PYPROJECT}"
     sed -i "s/+cu${CUDA_VERSION_COMPACT}\$//" "${PYLIBRAFT_VERSION_FILE}"
     sed -i "s/- libraft-gb10-cu${CUDA_VERSION_COMPACT:0:2}==/- libraft-cu${CUDA_VERSION_COMPACT:0:2}==/" "${DEPENDENCIES_YAML}"' EXIT

echo "Building pylibraft-gb10 wheel v${VERSION}+cu${CUDA_VERSION_COMPACT} for ${ARCH} (SM_${GB10_CUDA_ARCH} only)..."
SKBUILD_CMAKE_ARGS="-Draft_ROOT=${INSTALL_DIR};-DCMAKE_PREFIX_PATH=${INSTALL_DIR};-DCMAKE_CUDA_ARCHITECTURES=${GB10_CUDA_ARCH}" \
    pip wheel \
        --no-deps \
        --no-build-isolation \
        --wheel-dir "${DIST_DIR}" \
        "${PROJECT_ROOT}/python/pylibraft"

PYLIBRAFT_WHEEL="$(ls "${DIST_DIR}"/pylibraft*.whl 2>/dev/null | head -1)" || true
[[ -z "${PYLIBRAFT_WHEEL}" ]] && { echo "ERROR: pylibraft wheel not found" >&2; exit 1; }
echo "pylibraft wheel: $(basename "${PYLIBRAFT_WHEEL}") ($(du -sh "${PYLIBRAFT_WHEEL}" | awk '{print $1}'))"

# ── 3. Publish both wheels ─────────────────────────────────────────────────────
cd "${PROJECT_ROOT}"

RELEASE_NOTES_ARG=()
if [[ -f "${RELEASE_NOTES}" ]]; then
    RELEASE_NOTES_ARG=(--notes-file "${RELEASE_NOTES}")
else
    RELEASE_NOTES_ARG=(--notes "pylibraft-gb10-cu${CUDA_VERSION_COMPACT:0:2} + libraft-gb10-cu${CUDA_VERSION_COMPACT:0:2} ${VERSION}+cu${CUDA_VERSION_COMPACT} wheels for ${ARCH} / CUDA ${CUDA_VERSION} / SM_${GB10_CUDA_ARCH} (GB10 / DGX Spark)")
fi

echo "Publishing wheels to GitHub release ${RELEASE_TAG}..."
gh release create "${RELEASE_TAG}" \
    --repo zbrad/raft \
    --title "${RELEASE_TITLE}" \
    --target "gb10" \
    "${RELEASE_NOTES_ARG[@]}" \
    "${LIBRAFT_WHEEL}#$(basename "${LIBRAFT_WHEEL}")" \
    "${PYLIBRAFT_WHEEL}#$(basename "${PYLIBRAFT_WHEEL}")"

echo ""
echo "Release: https://github.com/zbrad/raft/releases/tag/${RELEASE_TAG}"
echo "Done."
