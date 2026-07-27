#!/bin/bash
# raft_cupy_build_rtx50xx.sh — thin wrapper; see gpu_tuned/gpu_tuned_cupy_build.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gpu_tuned/gpu_tuned_cupy_build.sh" rtx50xx "$@"
