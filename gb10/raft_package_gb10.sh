#!/bin/bash
# raft_package_gb10.sh — thin wrapper; see gpu_tuned/gpu_tuned_package.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gpu_tuned/gpu_tuned_package.sh" gb10 "$@"
