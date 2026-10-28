#!/bin/bash
# wheel_publish.sh <variant> -- publish the GitHub release that tuned/wheel_release.sh marked ready. It publishes exactly what the
# gates saw: it refuses unless the marker exists and HEAD, the notes and every asset are unchanged since wheel_release.sh ran
# (gpu_tuned_publish_ready). It builds, tests and packages nothing.
#
#   CUDA_TAG=cu134 bash tuned/wheel_publish.sh gb10
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -uo pipefail

GPU_TUNED_ARG_VARIANT="${1:?usage: tuned/wheel_publish.sh <variant>}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1
cd "${PROJECT_ROOT}" || exit 1

RELEASES_DIR="$(gpu_tuned_out_dir releases "${PROJECT_ROOT}" "${CUDA_TAG}")"
MARKER="${RELEASES_DIR}/RELEASE_READY_wheels_${GPU_TUNED_VARIANT}"
TAG="$(sed -n 's/^tag=//p' "${MARKER}" 2>/dev/null)"
gpu_tuned_publish_ready "${MARKER}" || exit 1

echo ""
echo "Release: https://github.com/zbrad/raft/releases/tag/${TAG}"
echo "Done."
