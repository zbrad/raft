#!/bin/bash
# raft_release_rtx50xx.sh — publish the RTX 50xx C++ tarball as a GitHub release.
# New (split out of the old generic wsl/raft_release_wsl.sh, which hardcoded
# the release title as "SM_120" with no per-GPU variant of its own — this is
# effectively that release, now with its own dedicated script and a title
# derived from RTX50_CUDA_ARCH instead of a literal).
#
# NOTE: untested — run on an x86_64 host with RTX 50xx + CUDA installed.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=raft_env_rtx50xx.sh
source "${PROJECT_ROOT}/rtx50xx/raft_env_rtx50xx.sh" || exit 1
cd "${PROJECT_ROOT}"

VERSION="$(cat "${PROJECT_ROOT}/VERSION")"
# Derive short version (e.g. 26.06.00 -> 26.6)
SHORT_VER="$(echo "${VERSION}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"
PKG_NAME="raft-${SHORT_VER}-x86_64-cuda${CUDA_VERSION_COMPACT}-rtx50xx"
RELEASE_TAG="v${SHORT_VER}.0-x86_64-cuda${CUDA_VERSION_COMPACT}-rtx50xx"

gh release create "${RELEASE_TAG}" --repo zbrad/raft \
  "${PKG_NAME}.tar.bz2#RAFT ${SHORT_VER} x86_64 CUDA ${CUDA_VERSION} binary package (RTX 50xx)" \
  "CHECKSUMS_rtx50xx#CHECKSUMS_rtx50xx" \
  --title "RAFT ${SHORT_VER} — x86_64 / CUDA ${CUDA_VERSION} / SM_${RTX50_CUDA_ARCH}" \
  --notes-file "RELEASE_NOTES_${SHORT_VER}_rtx50xx_cu${CUDA_VERSION_COMPACT}.md" \
  --target "native-builds"
