#!/bin/bash
export PATH=/home/zbrad/.local/bin:/usr/local/cuda-13.2/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${PROJECT_ROOT}"

git add \
  .vscode/settings.json \
  raft_build_wsl.sh \
  raft_test_wsl.sh \
  raft_package_wsl.sh \
  raft_release_wsl.sh \
  raft_sync_wsl.sh

git commit -m "build: refactor WSL scripts to use PROJECT_ROOT and add vscode settings

All WSL scripts now derive PROJECT_ROOT from their own location via
BASH_SOURCE[0], removing hardcoded /mnt/f paths. .vscode/settings.json
sets RAFT_PROJECT_ROOT env var and defaults terminal to WSL.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"

git push origin cu132
