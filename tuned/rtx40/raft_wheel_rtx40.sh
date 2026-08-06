#!/bin/bash
# raft_wheel_rtx40.sh — thin wrapper; see wheel.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/wheel.sh" rtx40 "$@"
