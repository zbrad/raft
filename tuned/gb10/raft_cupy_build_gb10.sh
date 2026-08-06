#!/bin/bash
# raft_cupy_build_gb10.sh — thin wrapper; see cupy_build.sh.
# Renamed from raft_cupy_build.sh for naming consistency with rtx40/rtx50.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/cupy_build.sh" gb10 "$@"
