#!/bin/bash
# raft_sync.sh — stage, commit, and push the native-builds tooling.
# Renamed from gb10/raft_sync_gb10.sh now that it syncs gpu_tuned/ + all
# three variant dirs, not just gb10. Uses pathspecs (not an enumerated file
# list) so newly added scripts are picked up automatically instead of
# silently going unsynced.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${PROJECT_ROOT}"

git add \
  .vscode/settings.json \
  gb10/ \
  gpu_tuned/ \
  rtx40xx/ \
  rtx50xx/

git commit -m "build: sync native-builds tooling

Assisted-by: Claude Sonnet 5"

git push origin native-builds
