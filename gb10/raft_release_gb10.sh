#!/bin/bash
# raft_release_gb10.sh — thin wrapper; see gpu_tuned/gpu_tuned_release.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gpu_tuned/gpu_tuned_release.sh" gb10 "$@"
