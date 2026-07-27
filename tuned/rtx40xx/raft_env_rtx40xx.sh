#!/bin/bash
# raft_env_rtx40xx.sh — thin wrapper; see env.sh.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/env.sh" rtx40xx || return 1 2>/dev/null || exit 1
