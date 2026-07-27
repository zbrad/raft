#!/bin/bash
# raft_wheel_gb10.sh — thin wrapper; see wheel.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/wheel.sh" gb10 "$@"
