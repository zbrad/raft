#!/bin/bash
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
ARCH="$(uname -m)"
# shellcheck source=raft_env_gb10.sh
source "${PROJECT_ROOT}/gb10/raft_env_gb10.sh" || exit 1
cd "${PROJECT_ROOT}"

VERSION="$(cat "${PROJECT_ROOT}/VERSION")"
# Derive short version (e.g. 26.06.00 -> 26.6)
SHORT_VER="$(echo "${VERSION}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"
PKG_NAME="raft-${SHORT_VER}-${ARCH}-cuda${CUDA_VERSION_COMPACT}"
RELEASE_TAG="v${SHORT_VER}.0-${ARCH}-cuda${CUDA_VERSION_COMPACT}"
CHECKSUMS_FILE="CHECKSUMS_${ARCH}"
# gb10 (not ARCH/"aarch64") + toolkit version, matching the rest of this
# repo's naming: aarch64 == gb10 specifically here, and the CUDA minor
# version varies release to release, so neither should be left implicit.
RELEASE_NOTES_FILE="RELEASE_NOTES_${SHORT_VER}_gb10_cu${CUDA_VERSION_COMPACT}.md"

# Target the stable "native-builds" branch (renamed from "gb10", which was
# already too narrow once rtx40xx/rtx50xx started living on the same
# branch) -- not a CUDA-version-named one, since the toolkit version changes
# over time (was cu132, now cu133) and re-deriving the target branch from it
# fragments history with every bump. The CUDA version still goes into the
# tag/package name below, same as before.
gh release create "${RELEASE_TAG}" --repo zbrad/raft \
  "${PKG_NAME}.tar.bz2#RAFT ${SHORT_VER} ${ARCH} CUDA ${CUDA_VERSION} binary package" \
  "${CHECKSUMS_FILE}#${CHECKSUMS_FILE}" \
  --title "RAFT ${SHORT_VER} — ${ARCH} / CUDA ${CUDA_VERSION} / SM_${GB10_CUDA_ARCH}" \
  --notes-file "${RELEASE_NOTES_FILE}" \
  --target "native-builds"
