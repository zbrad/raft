#!/bin/bash
# raft_wheel_rtx50xx.sh — build libraft-rtx50xx-cuXX + pylibraft-rtx50xx-cuXX
# wheels for RTX 50xx (SM_120, x86_64) and package them for release.
# Mirrors gb10/raft_wheel_gb10.sh — see that file for the full rationale on
# each step; only the variant-specific names differ here.
#
# NOTE: untested — run on an x86_64 host with RTX 50xx + CUDA installed.
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="rtx50xx"
# shellcheck source=raft_env_rtx50xx.sh
source "${PROJECT_ROOT}/rtx50xx/raft_env_rtx50xx.sh" || exit 1
INSTALL_DIR="${PROJECT_ROOT}/cpp/build-${ARCH}/install"
VERSION="$(cat "${PROJECT_ROOT}/VERSION")"
# Derive short version (e.g. 26.06.00 -> 26.6)
SHORT_VER="$(echo "${VERSION}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"
RELEASE_TAG="v${VERSION}-x86_64-cuda${CUDA_VERSION_COMPACT}-rtx50xx"
RELEASE_TITLE="RAFT ${SHORT_VER} — x86_64 / CUDA ${CUDA_VERSION} / SM_${RTX50_CUDA_ARCH} (RTX 50xx / Blackwell) wheels"
RELEASE_NOTES="${PROJECT_ROOT}/RELEASE_NOTES_${SHORT_VER}_rtx50xx.md"
DIST_DIR="${PROJECT_ROOT}/dist/rtx50xx"

# ── install build deps ─────────────────────────────────────────────────────────
echo "Installing build dependencies..."
pip install \
    --extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple \
    -r "${PROJECT_ROOT}/requirements-build-cuda13x.txt"

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

# ── 1. Build libraft-rtx50xx-cuXX ─────────────────────────────────────────────
# Strategy: pre-place libraft.so from the existing cmake install into the
# Python package directory (libraft/lib64/), same as gb10/raft_wheel_gb10.sh.
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
LIBRAFT_PYPROJECT="${PROJECT_ROOT}/python/libraft/pyproject.toml"
LIBRAFT_LOAD_PY="${PROJECT_ROOT}/python/libraft/libraft/load.py"
LIBRAFT_LIB64="${PROJECT_ROOT}/python/libraft/libraft/lib64"
LIBRAFT_SONAME="libraft_rtx50xx_cu${CUDA_VERSION_COMPACT}.so"
LIBRAFT_VERSION_FILE="$(readlink -f "${PROJECT_ROOT}/python/libraft/libraft/VERSION")"

echo "Extracting libraft.so from existing cmake install (no recompile)..."
mkdir -p "${LIBRAFT_LIB64}"
rm -rf /tmp/raft-rtx50xx-install
cmake --install "${PROJECT_ROOT}/cpp/build-${ARCH}" --prefix /tmp/raft-rtx50xx-install
if [[ ! -f /tmp/raft-rtx50xx-install/lib/libraft.so ]]; then
    echo "ERROR: cmake --install did not produce libraft.so" >&2
    exit 1
fi
verify_rtx50xx_arch /tmp/raft-rtx50xx-install/lib/libraft.so || exit 1
cp /tmp/raft-rtx50xx-install/lib/libraft.so "${LIBRAFT_LIB64}/${LIBRAFT_SONAME}"
rm -rf /tmp/raft-rtx50xx-install

# Patch: rename to libraft-rtx50xx, embed CUDA minor version in VERSION, point
# load.py at the renamed libraft_rtx50xx_cuXXX.so, disable GIT_COMMIT path lookup
sed -i \
    -e "s/^name = \"libraft\"/name = \"libraft-rtx50xx\"/" \
    -e "s/^matrix-entry = .*/matrix-entry = \"cuda_suffixed=true;use_cuda_wheels=true\"\ncommit-files = []/" \
    "${LIBRAFT_PYPROJECT}"
sed -i "s/\$/+cu${CUDA_VERSION_COMPACT}/" "${LIBRAFT_VERSION_FILE}"
sed -i "s/soname = \"libraft\.so\"/soname = \"${LIBRAFT_SONAME}\"/" "${LIBRAFT_LOAD_PY}"
trap 'sed -i \
    -e "s/^name = \"libraft-rtx50xx\"/name = \"libraft\"/" \
    -e "/^commit-files = \[\]/d" \
    "${LIBRAFT_PYPROJECT}"
     sed -i "s/+cu${CUDA_VERSION_COMPACT}\$//" "${LIBRAFT_VERSION_FILE}"
     sed -i "s/soname = \"libraft_rtx50xx_cu[0-9]*\.so\"/soname = \"libraft.so\"/" "${LIBRAFT_LOAD_PY}"
     rm -rf "${LIBRAFT_LIB64}"' EXIT

echo "Building libraft-rtx50xx wheel v${VERSION}+cu${CUDA_VERSION_COMPACT} for x86_64 (bundles libraft.so as ${LIBRAFT_SONAME})..."
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
    -e "s/^name = \"libraft-rtx50xx\"/name = \"libraft\"/" \
    -e "/^commit-files = \[\]/d" \
    "${LIBRAFT_PYPROJECT}"
sed -i "s/+cu${CUDA_VERSION_COMPACT}\$//" "${LIBRAFT_VERSION_FILE}"
sed -i "s/soname = \"libraft_rtx50xx_cu[0-9]*\.so\"/soname = \"libraft.so\"/" "${LIBRAFT_LOAD_PY}"
rm -rf "${LIBRAFT_LIB64}"
trap - EXIT

# ── 2. Build pylibraft-rtx50xx-cuXX ───────────────────────────────────────────
PYLIBRAFT_PYPROJECT="${PROJECT_ROOT}/python/pylibraft/pyproject.toml"
PYLIBRAFT_VERSION_FILE="$(readlink -f "${PROJECT_ROOT}/python/pylibraft/pylibraft/VERSION")"
DEPENDENCIES_YAML="${PROJECT_ROOT}/dependencies.yaml"

# Patch: rename to pylibraft-rtx50xx, embed CUDA minor version in VERSION,
# disable GIT_COMMIT path lookup. Same dependencies.yaml-not-pyproject.toml
# caveat as gb10/raft_wheel_gb10.sh — see that file for why.
sed -i \
    -e "s/^name = \"pylibraft\"/name = \"pylibraft-rtx50xx\"/" \
    -e "s/^matrix-entry = .*/matrix-entry = \"cuda_suffixed=true\"\ncommit-files = []/" \
    "${PYLIBRAFT_PYPROJECT}"
sed -i "s/\$/+cu${CUDA_VERSION_COMPACT}/" "${PYLIBRAFT_VERSION_FILE}"
sed -i "s/- libraft-cu${CUDA_VERSION_COMPACT:0:2}==/- libraft-rtx50xx-cu${CUDA_VERSION_COMPACT:0:2}==/" "${DEPENDENCIES_YAML}"
trap 'sed -i \
    -e "s/^name = \"pylibraft-rtx50xx\"/name = \"pylibraft\"/" \
    -e "/^commit-files = \[\]/d" \
    "${PYLIBRAFT_PYPROJECT}"
     sed -i "s/+cu${CUDA_VERSION_COMPACT}\$//" "${PYLIBRAFT_VERSION_FILE}"
     sed -i "s/- libraft-rtx50xx-cu${CUDA_VERSION_COMPACT:0:2}==/- libraft-cu${CUDA_VERSION_COMPACT:0:2}==/" "${DEPENDENCIES_YAML}"' EXIT

echo "Building pylibraft-rtx50xx wheel v${VERSION}+cu${CUDA_VERSION_COMPACT} for x86_64 (SM_${RTX50_CUDA_ARCH} only)..."
SKBUILD_CMAKE_ARGS="-Draft_ROOT=${INSTALL_DIR};-DCMAKE_PREFIX_PATH=${INSTALL_DIR};-DCMAKE_CUDA_ARCHITECTURES=${RTX50_CUDA_ARCH}" \
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
    RELEASE_NOTES_ARG=(--notes "pylibraft-rtx50xx-cu${CUDA_VERSION_COMPACT:0:2} + libraft-rtx50xx-cu${CUDA_VERSION_COMPACT:0:2} ${VERSION}+cu${CUDA_VERSION_COMPACT} wheels for x86_64 / CUDA ${CUDA_VERSION} / SM_${RTX50_CUDA_ARCH} (RTX 50xx / Blackwell)")
fi

echo "Publishing wheels to GitHub release ${RELEASE_TAG}..."
gh release create "${RELEASE_TAG}" \
    --repo zbrad/raft \
    --title "${RELEASE_TITLE}" \
    --target "native-builds" \
    "${RELEASE_NOTES_ARG[@]}" \
    "${LIBRAFT_WHEEL}#$(basename "${LIBRAFT_WHEEL}")" \
    "${PYLIBRAFT_WHEEL}#$(basename "${PYLIBRAFT_WHEEL}")"

echo ""
echo "Release: https://github.com/zbrad/raft/releases/tag/${RELEASE_TAG}"
echo "Done."
