#!/bin/bash
# raft_env_rtx50xx.sh — thin wrapper; see gpu_tuned/gpu_tuned_env.sh.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gpu_tuned/gpu_tuned_env.sh" rtx50xx || return 1 2>/dev/null || exit 1
