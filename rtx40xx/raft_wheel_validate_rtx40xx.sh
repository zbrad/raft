#!/bin/bash
# raft_wheel_validate_rtx40xx.sh — thin wrapper; see gpu_tuned/gpu_tuned_wheel_validate.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gpu_tuned/gpu_tuned_wheel_validate.sh" rtx40xx "$@"
