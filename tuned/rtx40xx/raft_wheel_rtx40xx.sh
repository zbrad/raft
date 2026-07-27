#!/bin/bash
# raft_wheel_rtx40xx.sh — thin wrapper; see wheel.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/wheel.sh" rtx40xx "$@"
