#!/bin/bash
# raft_cupy_build_rtx40xx.sh — thin wrapper; see cupy_build.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/cupy_build.sh" rtx40xx "$@"
