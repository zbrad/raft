#!/bin/bash
# raft_wheel_validate_rtx50xx.sh — thin wrapper; see wheel_validate.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/wheel_validate.sh" rtx50xx "$@"
