#!/bin/bash
# wheel_smoke_test.sh <variant> -- install the PACKAGED wheels (dist/release/, made by tuned/wheel_package.sh) into a scratch venv
# and exercise the compiled extensions, the same checks as tuned/wheel_validate.sh but on the files that will be published.
# Writes SMOKE_RESULTS_wheels_<variant>.log; tuned/wheel_release.sh requires its "Smoke test summary: passed" line.
#
#   CUDA_TAG=cu134 bash tuned/wheel_smoke_test.sh gb10
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GPU_TUNED_ARG_VARIANT="${1:?usage: tuned/wheel_smoke_test.sh <variant>}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=raft_wheel_common.sh
source "${PROJECT_ROOT}/tuned/raft_wheel_common.sh" || exit 1
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1

RELEASES_DIR="$(gpu_tuned_out_dir releases "${PROJECT_ROOT}" "${CUDA_TAG}")"
DIST_DIR="$(gpu_tuned_out_dir dist "${PROJECT_ROOT}" "${CUDA_TAG}" "${GPU_TUNED_ARG_VARIANT}")"
PKG_DIR="${DIST_DIR}/release"
LOG="${RELEASES_DIR}/SMOKE_RESULTS_wheels_${GPU_TUNED_ARG_VARIANT}.log"
[[ -f "${PKG_DIR}/wheel-package-info.txt" ]] || { echo "ERROR: ${PKG_DIR} not packaged. Run CUDA_TAG=${CUDA_TAG} bash tuned/wheel_package.sh ${GPU_TUNED_ARG_VARIANT} first." >&2; exit 1; }
for w in "${PKG_DIR}"/*.whl; do
    ( cd "${PKG_DIR}" && sha256sum -c --quiet "$(basename "${w}").sha256" ) || { echo "ERROR: $(basename "${w}") does not match its sha256 sidecar." >&2; exit 1; }
done

mkdir -p "${RELEASES_DIR}"
{
    echo "raft wheel smoke test -- variant=${GPU_TUNED_ARG_VARIANT} ${CUDA_TAG}"
    echo "wheels: $(ls "${PKG_DIR}" | grep -c '\.whl$') in ${PKG_DIR}"
    if validate_wheels "${PKG_DIR}" "3.14" "${GPU_TUNED_ARG_VARIANT}"; then
        echo "=== Smoke test summary: passed ==="
    else
        echo "=== Smoke test summary: FAILED ==="
    fi
} 2>&1 | tee "${LOG}"
grep -q 'Smoke test summary: passed' "${LOG}"
