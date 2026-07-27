#!/bin/bash
# raft_wheel_gb10.sh — thin wrapper; see gpu_tuned/gpu_tuned_wheel.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gpu_tuned/gpu_tuned_wheel.sh" gb10 "$@"
