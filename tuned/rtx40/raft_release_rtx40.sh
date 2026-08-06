#!/bin/bash
# raft_release_rtx40.sh — thin wrapper; see release.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/release.sh" rtx40 "$@"
