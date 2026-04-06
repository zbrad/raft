#!/bin/bash
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
ARCH="$(uname -m)"
# shellcheck source=raft_env_spark.sh
source "${PROJECT_ROOT}/spark/raft_env_spark.sh" || exit 1
cd "${PROJECT_ROOT}"

PKG_NAME="raft-26.6-${ARCH}-cuda${CUDA_VERSION_COMPACT}"
RELEASE_TAG="v26.6.0-${ARCH}-cuda${CUDA_VERSION_COMPACT}"
CHECKSUMS_FILE="CHECKSUMS_${ARCH}"
RELEASE_NOTES_FILE="RELEASE_NOTES_26.6_${ARCH}.md"

gh release create "${RELEASE_TAG}" --repo zbrad/raft \
  "${PKG_NAME}.tar.bz2#RAFT 26.6 ${ARCH} CUDA ${CUDA_VERSION} binary package" \
  "${CHECKSUMS_FILE}#${CHECKSUMS_FILE}" \
  --title "RAFT 26.6 — ${ARCH} / CUDA ${CUDA_VERSION} / SM_120a" \
  --notes-file "${RELEASE_NOTES_FILE}" \
  --target "cu${CUDA_VERSION_COMPACT}"
