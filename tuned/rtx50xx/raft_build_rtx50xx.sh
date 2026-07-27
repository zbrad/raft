#!/bin/bash
# raft_build_rtx50xx.sh — thin wrapper; see build.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build.sh" rtx50xx "$@"
