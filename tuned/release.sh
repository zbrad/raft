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

# tr -d '\r': matches tuned/package.sh's own defensive strip (see that
# file's comment) -- must compute VERSION identically here since this
# script doesn't rebuild/repackage, it just publishes whatever
# tuned/package.sh already produced under this exact name.
VERSION="$(tr -d '\r' < "${PROJECT_ROOT}/VERSION")"
# Derive short version (e.g. 26.08.00 -> 26.8) -- raft's own long-standing
# convention (older tags, RELEASE_NOTES_26.8_*.md); must match
# tuned/package.sh's own SHORT_VER computation exactly.
SHORT_VER="$(echo "${VERSION}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"
# <short_ver>-<variant>-<cuda_tag>: variant-then-cuda_tag order matches
# zbrad/cuvs's release-tag order (v${CUVS_VERSION}-${GPU_TUNED_VARIANT}-
# ${CUDA_TAG} there); short (not full) version is raft's own convention.
# Must match tuned/package.sh's own PKG_NAME computation exactly
# (independent, not passed between the two scripts -- same pattern as
# RELEASE_NOTES_FILE below).
PKG_NAME="raft-${SHORT_VER}-${GPU_TUNED_VARIANT}-${CUDA_TAG}"
RELEASE_TAG="v${SHORT_VER}-${GPU_TUNED_VARIANT}-${CUDA_TAG}"
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
