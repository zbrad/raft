#!/bin/bash
# raft_release_rtx40xx.sh — publish the RTX 40xx C++ tarball as a GitHub release.
# Renamed/fixed from wsl/raft_release_wsl.sh, which hardcoded the release
# title as "SM_120" regardless of which GPU the tarball was actually built
# for — misleading now that rtx40xx (SM_89) and rtx50xx (SM_120) both exist.
#
# NOTE: untested — run on an x86_64 host with RTX 40xx + CUDA installed.
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=raft_env_rtx40xx.sh
source "${PROJECT_ROOT}/rtx40xx/raft_env_rtx40xx.sh" || exit 1
cd "${PROJECT_ROOT}"

PKG_NAME="raft-26.6-x86_64-cuda${CUDA_VERSION_COMPACT}-rtx40xx"
RELEASE_TAG="v26.6.0-x86_64-cuda${CUDA_VERSION_COMPACT}-rtx40xx"

gh release create "${RELEASE_TAG}" --repo zbrad/raft \
  "${PKG_NAME}.tar.bz2#RAFT 26.6 x86_64 CUDA ${CUDA_VERSION} binary package (RTX 40xx)" \
  "CHECKSUMS_rtx40xx#CHECKSUMS_rtx40xx" \
  --title "RAFT 26.6 — x86_64 / CUDA ${CUDA_VERSION} / SM_${RTX40_CUDA_ARCH}" \
  --notes-file RELEASE_NOTES_26.6_rtx40xx.md \
  --target cu132
