#!/bin/bash
# raft_package_rtx50xx.sh — thin wrapper; see package.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/package.sh" rtx50xx "$@"
