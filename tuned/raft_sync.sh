#!/bin/bash
# raft_sync.sh — stage, commit, and push the tuned-builds tooling.
# Renamed from gb10/raft_sync_gb10.sh now that it syncs all of tuned/, not
# just gb10. Enumerated rather than a blanket `git add tuned/` so that
# generated per-release artifacts (CHECKSUMS_<variant>, hand-dropped
# RELEASE_NOTES_*.md under tuned/releases/) don't get silently staged --
# this script syncs tooling, not release-run output.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

git add \
  .vscode/settings.json \
  tuned/gb10/ \
  tuned/rtx40/ \
  tuned/rtx50/ \
  tuned/devices/ \
  tuned/*.sh \
  tuned/requirements-build-cuda13x.txt \
  tuned/releases/CHECKSUMS \
  tuned/releases/CHECKSUMS_x86_64 \
  tuned/releases/INSTALL_GUIDE_26.6_aarch64.md \
  tuned/releases/RELEASE_INDEX_26.6_aarch64.md \
  tuned/releases/RELEASE_INDEX_26.6_x86_64.md \
  tuned/releases/RELEASE_NOTES_26.6_aarch64.md \
  tuned/releases/RELEASE_NOTES_26.6_x86_64.md \
  tuned/releases/RELEASE_README_26.6_aarch64.md \
  tuned/releases/RELEASE_README_26.6_x86_64.md

git commit -m "build: sync tuned-builds tooling

Assisted-by: Claude Sonnet 5"

git push origin tuned-builds
