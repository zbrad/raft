#!/bin/bash
# wheel_release.sh <variant> -- the release gates for the Python wheels tuned/wheel_package.sh made. Stage order:
#   wheel.sh -> wheel_validate.sh -> wheel_package.sh -> wheel_smoke_test.sh -> (review and commit
#   tuned/releases/RELEASE_NOTES_<version>.md) -> this -> wheel_publish.sh
# It never builds, tests, packages or publishes (docs/ARCHITECTURE.md B3, I5). If every gate passes it writes the ready-marker
# (RELEASE_READY_wheels_<variant>); tuned/wheel_publish.sh <variant> publishes exactly what the gates saw. The gates are the
# common ones in tuned-common (gpu_tuned_release_gates) plus a check that every packaged wheel matches its sha256 sidecar.
#
#   CUDA_TAG=cu134 bash tuned/wheel_release.sh gb10
#
# The release is named by the wheels' date label (v<version>), read from wheel-package-info.txt and never recomputed here.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -uo pipefail

GPU_TUNED_ARG_VARIANT="${1:?usage: tuned/wheel_release.sh <variant>}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1
cd "${PROJECT_ROOT}" || exit 1

RELEASES_DIR="$(gpu_tuned_out_dir releases "${PROJECT_ROOT}" "${CUDA_TAG}")"
DIST_DIR="$(gpu_tuned_out_dir dist "${PROJECT_ROOT}" "${CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
PKG_DIR="${DIST_DIR}/release"
INFO="${PKG_DIR}/wheel-package-info.txt"
TEST_LOG="${RELEASES_DIR}/TEST_RESULTS_wheels_${GPU_TUNED_VARIANT}.log"
SMOKE_LOG="${RELEASES_DIR}/SMOKE_RESULTS_wheels_${GPU_TUNED_VARIANT}.log"
MARKER="${RELEASES_DIR}/RELEASE_READY_wheels_${GPU_TUNED_VARIANT}"
gpu_tuned_release_marker_clear "${MARKER}"

if [[ ! -f "${INFO}" ]]; then
    echo "ERROR: ${INFO} not found -- run 'CUDA_TAG=${CUDA_TAG} bash tuned/wheel_package.sh ${GPU_TUNED_VARIANT}' at the commit being released first." >&2
    exit 1
fi
info() { sed -n "s/^$1=//p" "${INFO}"; }
RELEASE_TAG="$(info release_tag)"; PACKAGED_COMMIT="$(info commit)"; BASE_VERSION="$(info upstream_version)"; MAIN="$(info main_wheel)"
RELEASE_NOTES_FILE="tuned/releases/RELEASE_NOTES_${RELEASE_TAG#v}.md"
RELEASE_TITLE="RAFT ${BASE_VERSION} Python wheels — ${GPU_TUNED_VARIANT} ${CUDA_TAG} (${RELEASE_TAG#v}) — ${GPU_TUNED_HW_LABEL}"

ASSETS=()
SIDECAR_BAD=""
while IFS= read -r name; do
    ASSETS+=("${PKG_DIR}/${name}#${name}" "${PKG_DIR}/${name}.sha256#${name}.sha256")
    gpu_tuned_verify_sha256_sidecar "${PKG_DIR}/${name}" 2>/dev/null || SIDECAR_BAD="${SIDECAR_BAD} ${name}"
done < <(info wheel)

echo "Release ${RELEASE_TAG} (RAFT ${BASE_VERSION} wheels, packaged at ${PACKAGED_COMMIT}):"

gpu_tuned_release_gates tag="${RELEASE_TAG}" variant="${GPU_TUNED_VARIANT}" cuda="${CUDA_TAG}" info="${INFO}" \
    built="${DIST_DIR}/${MAIN}" test_log="${TEST_LOG}" test_pass='^Wheel validation passed\.$' \
    tarball="${PKG_DIR}/${MAIN}" smoke_log="${SMOKE_LOG}" notes="${RELEASE_NOTES_FILE}" packaged="${PACKAGED_COMMIT}" \
    || { echo "" >&2; echo "ERROR: a release gate failed; nothing was published (and no ready-marker was written)." >&2; exit 1; }
if [[ -n "${SIDECAR_BAD}" ]]; then
    echo "  FAIL: a packaged wheel does not match its sha256 sidecar:${SIDECAR_BAD}" >&2
    echo "ERROR: a release gate failed; nothing was published (and no ready-marker was written)." >&2
    exit 1
fi
echo "  ok:   all $(info wheel | wc -l) packaged wheels match their sha256 sidecars"

echo ""
gpu_tuned_release_ready "${MARKER}" "zbrad/raft" "${RELEASE_TAG}" "${RELEASE_TITLE}" \
    "${RELEASE_NOTES_FILE}" "${ASSETS[@]}" \
    "${TEST_LOG}#Wheel validation results (${GPU_TUNED_VARIANT})" \
    "${SMOKE_LOG}#Packaged wheel smoke test results (${GPU_TUNED_VARIANT})" || exit 1

echo "Done."
