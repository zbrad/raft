#!/bin/bash
# publish.sh <variant> — publishes the GitHub release that tuned/release.sh <variant> gated, and nothing else.
# It publishes only what release.sh's gates saw: it reads the ready-marker RELEASE_READY_<variant> and refuses
# unless HEAD, the release notes and every asset are unchanged since release.sh passed (gpu_tuned_publish_ready).
# After publishing it renames the marker spent, so one passing release.sh run publishes once. With no marker it
# does nothing: run tuned/release.sh <variant> first.
set -uo pipefail
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GPU_TUNED_ARG_VARIANT="${1:-}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1
cd "${PROJECT_ROOT}"

RELEASES_DIR="$(gpu_tuned_out_dir releases "${PROJECT_ROOT}" "${CUDA_TAG}")"
READY_MARKER="${RELEASES_DIR}/RELEASE_READY_${GPU_TUNED_VARIANT}"

gpu_tuned_publish_ready "${READY_MARKER}" || exit 1
echo "Release: https://github.com/zbrad/raft/releases/tag/$(sed -n 's/^tag=//p' "${READY_MARKER}.published")"
