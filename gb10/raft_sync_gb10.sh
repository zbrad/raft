#!/bin/bash
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

git add \
  .vscode/settings.json \
  gb10/raft_env_gb10.sh \
  gb10/raft_build_gb10.sh \
  gb10/raft_regression_test_gb10.sh \
  gb10/raft_package_gb10.sh \
  gb10/raft_release_gb10.sh \
  gb10/raft_wheel_gb10.sh \
  gb10/raft_sync_gb10.sh

git commit -m "build: add gb10/ scripts for build, test, package, wheel, and release

Assisted-by: Claude Sonnet 5"

git push origin gb10
