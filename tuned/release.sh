#!/bin/bash
# release.sh <variant> — publish the given GPU variant's C++
# tarball as a GitHub release. Shared implementation behind every
# gb10/rtx40/rtx50 raft_release_<variant>.sh wrapper.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GPU_TUNED_ARG_VARIANT="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1
cd "${PROJECT_ROOT}"

VERSION="$(cat "${PROJECT_ROOT}/VERSION")"
# Derive short version (e.g. 26.06.00 -> 26.6)
SHORT_VER="$(echo "${VERSION}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"
PKG_NAME="raft-${SHORT_VER}-cuda${CUDA_VERSION_COMPACT}-${GPU_TUNED_VARIANT}"
RELEASE_TAG="v${SHORT_VER}.0-cuda${CUDA_VERSION_COMPACT}-${GPU_TUNED_VARIANT}"
# Canonical release-notes filename (WITH the _cu<N> suffix, since the CUDA
# minor version varies release to release and shouldn't be left implicit)
# -- wheel.sh derives this identically, independently (they're
# separate invocations for two different releases, not passed between
# each other; the fix is that both compute it via the same one-line
# expression, not that one produces it for the other).
RELEASE_NOTES_FILE="tuned/releases/RELEASE_NOTES_${SHORT_VER}_${GPU_TUNED_VARIANT}_cu${CUDA_VERSION_COMPACT}.md"

gh release create "${RELEASE_TAG}" --repo zbrad/raft \
  "${PKG_NAME}.tar.bz2#RAFT ${SHORT_VER} CUDA ${CUDA_VERSION} binary package (${GPU_TUNED_DEVICE_LABEL})" \
  "tuned/releases/CHECKSUMS_${GPU_TUNED_VARIANT}#CHECKSUMS_${GPU_TUNED_VARIANT}" \
  --title "RAFT ${SHORT_VER} — ${GPU_TUNED_DEVICE_LABEL} / CUDA ${CUDA_VERSION} / SM_${GPU_TUNED_CUDA_ARCH}" \
  --notes-file "${RELEASE_NOTES_FILE}" \
  --target "tuned-builds"
