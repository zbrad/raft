#!/bin/bash
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

git add \
  .vscode/settings.json \
  spark/raft_env_spark.sh \
  spark/raft_build_spark.sh \
  spark/raft_test_spark.sh \
  spark/raft_package_spark.sh \
  spark/raft_release_spark.sh \
  spark/raft_wheel_spark.sh \
  spark/raft_sync_spark.sh

git commit -m "build: add spark/ scripts for build, test, package, wheel, and release

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"

git push origin cu132
