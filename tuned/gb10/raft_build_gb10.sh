#!/bin/bash
# raft_build_gb10.sh — thin wrapper; see build.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build.sh" gb10 "$@"
