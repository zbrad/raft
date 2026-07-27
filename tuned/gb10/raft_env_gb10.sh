#!/bin/bash
# raft_env_gb10.sh — thin wrapper; see env.sh.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/env.sh" gb10 || return 1 2>/dev/null || exit 1
