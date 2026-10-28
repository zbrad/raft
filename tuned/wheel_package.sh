#!/bin/bash
# wheel_package.sh <variant> -- package the wheels tuned/wheel.sh built and tuned/wheel_validate.sh tested: copy the five wheels
# (libraft, pylibraft, raft-dask for the variant, and the shared librmm, rmm) into dist/release/, write a sha256 sidecar for
# each, wheel-package-info.txt and, if no notes are tracked yet, a DRAFT release-notes file. It never builds, tests, tags or
# publishes (docs/ARCHITECTURE.md B3). Stage order for the wheels:
#   wheel.sh -> wheel_validate.sh -> wheel_package.sh -> wheel_smoke_test.sh -> (review and commit the notes)
#   -> wheel_release.sh -> wheel_publish.sh
#
#   CUDA_TAG=cu134 bash tuned/wheel_package.sh gb10
#
# The release is named by the wheels' own date label (tag v<version>, the version ending +<variant>.cu<cuda>.<YYYYMMDD>[.<seq>]),
# allocated by wheel.sh and read from dist/wheel-version.txt; it is never recomputed here. The native C++ tarball has its own
# tag and its own package.sh; the two release independently.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -euo pipefail

GPU_TUNED_ARG_VARIANT="${1:?usage: tuned/wheel_package.sh <variant>}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1
cd "${PROJECT_ROOT}"

RELEASES_DIR="$(gpu_tuned_out_dir releases "${PROJECT_ROOT}" "${CUDA_TAG}")"
DIST_DIR="$(gpu_tuned_out_dir dist "${PROJECT_ROOT}" "${CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
PKG_DIR="${DIST_DIR}/release"
TEST_LOG="${RELEASES_DIR}/TEST_RESULTS_wheels_${GPU_TUNED_VARIANT}.log"

# The wheels were built in this venv: its setuptools must meet the common minimum (H10).
gpu_tuned_check_venv_setuptools "${GPU_TUNED_VENV_DIR}" || exit 1

[[ -f "${DIST_DIR}/wheel-version.txt" ]] || { echo "ERROR: ${DIST_DIR}/wheel-version.txt not found. Run CUDA_TAG=${CUDA_TAG} bash tuned/wheel.sh ${GPU_TUNED_VARIANT} first." >&2; exit 1; }
grep -qx 'Wheel validation passed\.' "${TEST_LOG}" 2>/dev/null \
    || { echo "ERROR: no passing ${TEST_LOG}. Run CUDA_TAG=${CUDA_TAG} bash tuned/wheel_validate.sh ${GPU_TUNED_VARIANT} first." >&2; exit 1; }

# The three variant wheels share one version; the shared librmm/rmm pair carries its own label.
pick() { local w; w="$(ls "${DIST_DIR}"/$1 2>/dev/null | head -1)"; [[ -n "${w}" ]] || { echo "ERROR: no $1 in ${DIST_DIR}; run tuned/wheel.sh first." >&2; exit 1; }; echo "${w}"; }
LIBRAFT="$(pick "libraft_${GPU_TUNED_VARIANT}_*.whl")"
PYLIBRAFT="$(pick "pylibraft_${GPU_TUNED_VARIANT}_*.whl")"
RAFT_DASK="$(pick "raft_dask_${GPU_TUNED_VARIANT}_*.whl")"
LIBRMM="$(pick 'librmm_*.whl')"
RMM="$(pick 'rmm_*.whl')"
VERSION="$(gpu_tuned_wheel_version "${LIBRAFT}" "libraft_${GPU_TUNED_VARIANT}_cu13")"
for w in "${PYLIBRAFT}:pylibraft_${GPU_TUNED_VARIANT}_cu13" "${RAFT_DASK}:raft_dask_${GPU_TUNED_VARIANT}_cu13"; do
    v="$(gpu_tuned_wheel_version "${w%%:*}" "${w##*:}")"
    [[ "${v}" == "${VERSION}" ]] || { echo "ERROR: $(basename "${w%%:*}") is version ${v}; every variant wheel must be ${VERSION}." >&2; exit 1; }
done
[[ "${VERSION}" == *"+${GPU_TUNED_VARIANT}.cu${CUDA_VERSION_COMPACT}."* ]] \
    || { echo "ERROR: version ${VERSION} does not carry +${GPU_TUNED_VARIANT}.cu${CUDA_VERSION_COMPACT}.<label>." >&2; exit 1; }
for w in "${LIBRAFT}" "${PYLIBRAFT}" "${RAFT_DASK}" "${LIBRMM}" "${RMM}"; do gpu_tuned_check_wheel_label "${w}"; done
RELEASE_TAG="v${VERSION}"
gpu_tuned_check_release_tag "${RELEASE_TAG}"
BASE_VERSION="${VERSION%%+*}"

# H6: the wheels are built from the native build tree at HEAD; HEAD may differ from the packaged commit only in tuned/.
COMMIT="$(git rev-parse --short=9 HEAD)"
git diff --quiet HEAD -- . ':!tuned/releases' || { echo "ERROR: the tracked tree differs from HEAD; commit first so the package names a commit." >&2; exit 1; }

rm -rf "${PKG_DIR}"
mkdir -p "${PKG_DIR}"
for w in "${LIBRAFT}" "${PYLIBRAFT}" "${RAFT_DASK}" "${LIBRMM}" "${RMM}"; do
    cp "${w}" "${PKG_DIR}/"
    ( cd "${PKG_DIR}" && sha256sum "$(basename "${w}")" > "$(basename "${w}").sha256" )
done
MAIN="$(basename "${LIBRAFT}")"
{
    echo "release_tag=${RELEASE_TAG}"
    echo "upstream_version=${BASE_VERSION}"
    echo "wheel_version=${VERSION}"
    echo "commit=${COMMIT}"
    echo "cuda_tag=${CUDA_TAG}"
    echo "variant=${GPU_TUNED_VARIANT}"
    echo "main_wheel=${MAIN}"
    echo "sha256=$(sha256sum "${PKG_DIR}/${MAIN}" | awk '{print $1}')"
    for w in "${LIBRAFT}" "${PYLIBRAFT}" "${RAFT_DASK}" "${LIBRMM}" "${RMM}"; do echo "wheel=$(basename "${w}")"; done
} > "${PKG_DIR}/wheel-package-info.txt"

NOTES="tuned/releases/RELEASE_NOTES_${RELEASE_TAG#v}.md"
if [[ ! -f "${NOTES}" ]]; then
    {
        echo '<!-- DRAFT — not yet published: review, then delete this line and commit -->'
        echo "# RAFT ${BASE_VERSION} Python wheels — ${GPU_TUNED_HW_LABEL} (CUDA ${CUDA_VERSION}) — ${RELEASE_TAG}"
        echo ""
        echo "**Wheels**: $(for w in "${LIBRAFT}" "${PYLIBRAFT}" "${RAFT_DASK}" "${LIBRMM}" "${RMM}"; do printf '`%s` ' "$(basename "${w}")"; done)· built at \`${COMMIT}\`"
        echo ""
        echo "## This release"
        echo ""
        echo "_Author: describe what changed in this release, then delete this line._"
    } > "${NOTES}"
    echo "Draft release notes written (review, then commit): ${NOTES}"
fi
echo ""
echo "Packaged (not published): ${PKG_DIR} (${RELEASE_TAG}, 5 wheels)"
echo "Next: bash tuned/wheel_smoke_test.sh ${GPU_TUNED_VARIANT}, then tuned/wheel_release.sh, then tuned/wheel_publish.sh"
