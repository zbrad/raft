#!/bin/bash
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="$(uname -m)"
# shellcheck source=raft_env_spark.sh
source "${PROJECT_ROOT}/spark/raft_env_spark.sh" || exit 1
INSTALL_DIR="${PROJECT_ROOT}/cpp/build-${ARCH}/install"
VERSION="$(cat "${PROJECT_ROOT}/VERSION")"
# Derive short version (e.g. 26.06.00 -> 26.6)
SHORT_VER="$(echo "${VERSION}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"
RELEASE_TAG="v${VERSION}-${ARCH}-cuda${CUDA_VERSION_COMPACT}-spark"
RELEASE_TITLE="RAFT ${SHORT_VER} — ${ARCH} / CUDA ${CUDA_VERSION} / SM_121 (DGX Spark) wheels"
RELEASE_NOTES="${PROJECT_ROOT}/RELEASE_NOTES_${SHORT_VER}_${ARCH}.md"
DIST_DIR="${PROJECT_ROOT}/dist/spark"

# ── helpers ────────────────────────────────────────────────────────────────────

# ── install build deps ─────────────────────────────────────────────────────────
echo "Installing build dependencies..."
pip install \
    --extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple \
    -r "${PROJECT_ROOT}/requirements-build-cuda132.txt"

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

# ── 1. Build libraft-cu13 ─────────────────────────────────────────────────────
# Strategy: pre-place libraft.so from the existing cmake install into the Python
# package directory (libraft/lib64/).  scikit-build-core includes all files from
# wheel.packages, so the .so gets bundled.  Setting CMAKE_PREFIX_PATH makes
# find_package(raft) succeed and return early — no C++ recompilation needed.
# We keep the original "libraft" name so pip can satisfy the
# pylibraft-spark-cu13 dependency "libraft-cu13==26.6.*".
LIBRAFT_PYPROJECT="${PROJECT_ROOT}/python/libraft/pyproject.toml"
LIBRAFT_LIB64="${PROJECT_ROOT}/python/libraft/libraft/lib64"

echo "Extracting libraft.so from existing cmake install (no recompile)..."
mkdir -p "${LIBRAFT_LIB64}"
rm -rf /tmp/raft-spark-install
cmake --install "${PROJECT_ROOT}/cpp/build-${ARCH}" --prefix /tmp/raft-spark-install
if [[ ! -f /tmp/raft-spark-install/lib/libraft.so ]]; then
    echo "ERROR: cmake --install did not produce libraft.so" >&2
    exit 1
fi
cp /tmp/raft-spark-install/lib/libraft.so "${LIBRAFT_LIB64}/libraft.so"
rm -rf /tmp/raft-spark-install

# Patch: disable GIT_COMMIT path lookup (no name rename needed)
sed -i \
    -e "s/^matrix-entry = .*/matrix-entry = \"cuda_suffixed=true;use_cuda_wheels=true\"\ncommit-files = []/" \
    "${LIBRAFT_PYPROJECT}"
trap 'sed -i \
    -e "/^commit-files = \[\]/d" \
    "${LIBRAFT_PYPROJECT}"
     rm -rf "${LIBRAFT_LIB64}"' EXIT

echo "Building libraft-cu13 wheel v${VERSION} for ${ARCH} (bundles libraft.so)..."
SKBUILD_CMAKE_ARGS="-DCMAKE_PREFIX_PATH=${INSTALL_DIR}" \
    pip wheel \
        --no-deps \
        --no-build-isolation \
        --wheel-dir "${DIST_DIR}" \
        "${PROJECT_ROOT}/python/libraft"

LIBRAFT_WHEEL="$(ls "${DIST_DIR}"/libraft*.whl 2>/dev/null | head -1)"
[[ -z "${LIBRAFT_WHEEL}" ]] && { echo "ERROR: libraft wheel not found" >&2; exit 1; }
echo "libraft wheel: $(basename "${LIBRAFT_WHEEL}") ($(du -sh "${LIBRAFT_WHEEL}" | awk '{print $1}'))"

# Restore libraft pyproject.toml and lib64 before pylibraft build
sed -i -e "/^commit-files = \[\]/d" "${LIBRAFT_PYPROJECT}"
rm -rf "${LIBRAFT_LIB64}"
trap - EXIT

# ── 2. Build pylibraft-spark-cu13 ─────────────────────────────────────────────
PYLIBRAFT_PYPROJECT="${PROJECT_ROOT}/python/pylibraft/pyproject.toml"

# Patch: rename to pylibraft-spark, disable GIT_COMMIT path lookup
sed -i \
    -e "s/^name = \"pylibraft\"/name = \"pylibraft-spark\"/" \
    -e "s/^matrix-entry = .*/matrix-entry = \"cuda_suffixed=true\"\ncommit-files = []/" \
    "${PYLIBRAFT_PYPROJECT}"
trap 'sed -i \
    -e "s/^name = \"pylibraft-spark\"/name = \"pylibraft\"/" \
    -e "/^commit-files = \[\]/d" \
    "${PYLIBRAFT_PYPROJECT}"' EXIT

echo "Building pylibraft-spark-cu13 wheel v${VERSION} for ${ARCH} (SM_121 only)..."
SKBUILD_CMAKE_ARGS="-Draft_ROOT=${INSTALL_DIR};-DCMAKE_PREFIX_PATH=${INSTALL_DIR};-DCMAKE_CUDA_ARCHITECTURES=121" \
    pip wheel \
        --no-deps \
        --no-build-isolation \
        --wheel-dir "${DIST_DIR}" \
        "${PROJECT_ROOT}/python/pylibraft"

PYLIBRAFT_WHEEL="$(ls "${DIST_DIR}"/pylibraft*.whl 2>/dev/null | head -1)"
[[ -z "${PYLIBRAFT_WHEEL}" ]] && { echo "ERROR: pylibraft wheel not found" >&2; exit 1; }
echo "pylibraft wheel: $(basename "${PYLIBRAFT_WHEEL}") ($(du -sh "${PYLIBRAFT_WHEEL}" | awk '{print $1}'))"

# ── 3. Publish both wheels ─────────────────────────────────────────────────────
cd "${PROJECT_ROOT}"

RELEASE_NOTES_ARG=()
if [[ -f "${RELEASE_NOTES}" ]]; then
    RELEASE_NOTES_ARG=(--notes-file "${RELEASE_NOTES}")
else
    RELEASE_NOTES_ARG=(--notes "pylibraft-spark-cu13 + libraft-spark-cu13 ${VERSION} wheels for ${ARCH} / CUDA ${CUDA_VERSION} / SM_121 (DGX Spark)")
fi

echo "Publishing wheels to GitHub release ${RELEASE_TAG}..."
gh release create "${RELEASE_TAG}" \
    --repo zbrad/raft \
    --title "${RELEASE_TITLE}" \
    "${RELEASE_NOTES_ARG[@]}" \
    "${LIBRAFT_WHEEL}#$(basename "${LIBRAFT_WHEEL}")" \
    "${PYLIBRAFT_WHEEL}#$(basename "${PYLIBRAFT_WHEEL}")"

echo ""
echo "Release: https://github.com/zbrad/raft/releases/tag/${RELEASE_TAG}"
echo "Done."
