#!/bin/bash
export PATH=~/.local/bin:/usr/local/cuda-13.2/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

git add \
  .vscode/settings.json \
  wsl/raft_build_wsl.sh \
  wsl/raft_test_wsl.sh \
  wsl/raft_package_wsl.sh \
  wsl/raft_release_wsl.sh \
  wsl/raft_sync_wsl.sh

git commit -m "build: move WSL scripts to wsl/ subfolder and update PROJECT_ROOT paths

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"

git push origin cu132
