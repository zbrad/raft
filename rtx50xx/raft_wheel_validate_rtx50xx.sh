#!/bin/bash
# raft_wheel_validate_rtx50xx.sh — install the built rtx50xx wheels into a
# fresh scratch venv and exercise the actual compiled extensions (not just
# import them). Run after raft_wheel_rtx50xx.sh, before publishing.
#
# This is the concrete implementation of the "install into a scratch venv
# and import pylibraft" verification step from the original rtx50xx task
# list -- formalized as its own script after doing it ad hoc caught a real
# bug: libraft-rtx50xx-cu13's own dependency on librmm==26.8.* pulled in
# an ABI-mismatched upstream librmm (raft's C++ build fetches a newer RMM
# via CPM than that pin expects), which only surfaced as
# "undefined symbol: ...pool_memory_resource_impl..." when something
# actually called into pylibraft's compiled extension -- a bare
# `import pylibraft` succeeded regardless. See
# variant_wheel_build_pattern project memory (github-com-zbrad-raft) for
# the full story.
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../raft_wheel_common.sh
source "${PROJECT_ROOT}/raft_wheel_common.sh" || exit 1

validate_wheels "${PROJECT_ROOT}/dist/rtx50xx" "3.14" "rtx50xx"
