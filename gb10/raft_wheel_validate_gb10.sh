#!/bin/bash
# raft_wheel_validate_gb10.sh — install the built gb10 wheels into a fresh
# scratch venv and exercise the actual compiled extensions (not just import
# them). Run after raft_wheel_gb10.sh, before publishing. Mirrors
# rtx50xx/raft_wheel_validate_rtx50xx.sh, which is fully verified end-to-end
# on real hardware; this variant is untested against real GB10 hardware.
#
# See variant_wheel_build_pattern project memory (github-com-zbrad-raft) for
# the full story of the bugs this exact validation step caught on rtx50xx.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../raft_wheel_common.sh
source "${PROJECT_ROOT}/raft_wheel_common.sh" || exit 1

validate_wheels "${PROJECT_ROOT}/dist/gb10" "3.14" "gb10"
