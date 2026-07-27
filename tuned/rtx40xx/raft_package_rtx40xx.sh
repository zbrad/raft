#!/bin/bash
# raft_package_rtx40xx.sh — thin wrapper; see package.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/package.sh" rtx40xx "$@"
