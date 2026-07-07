#!/bin/bash
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
ARCH="$(uname -m)"
# shellcheck source=raft_env_gb10.sh
source "${PROJECT_ROOT}/gb10/raft_env_gb10.sh" || exit 1
cd "${PROJECT_ROOT}"

PKG_NAME="raft-26.6-${ARCH}-cuda${CUDA_VERSION_COMPACT}"
RELEASE_TAG="v26.6.0-${ARCH}-cuda${CUDA_VERSION_COMPACT}"
CHECKSUMS_FILE="CHECKSUMS_${ARCH}"
RELEASE_NOTES_FILE="RELEASE_NOTES_26.6_${ARCH}.md"

# Target the stable "gb10" branch, not a CUDA-version-named one -- the CUDA
# toolkit version changes over time (was cu132, now cu133) and re-deriving
# the target branch from it fragments history with every bump. The CUDA
# version still goes into the tag/package name below, same as before.
gh release create "${RELEASE_TAG}" --repo zbrad/raft \
  "${PKG_NAME}.tar.bz2#RAFT 26.6 ${ARCH} CUDA ${CUDA_VERSION} binary package" \
  "${CHECKSUMS_FILE}#${CHECKSUMS_FILE}" \
  --title "RAFT 26.6 — ${ARCH} / CUDA ${CUDA_VERSION} / SM_${GB10_CUDA_ARCH}" \
  --notes-file "${RELEASE_NOTES_FILE}" \
  --target "gb10"
