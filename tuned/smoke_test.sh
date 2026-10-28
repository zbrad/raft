#!/bin/bash
# smoke_test.sh <variant> — prove the PACKAGED tarball works, before it is released. Extracts the
# tarball tuned/package.sh made (named in package-info.txt) into a temporary directory and checks:
#   1. the tarball's sha256 matches package-info.txt and CHECKSUMS_<variant>;
#   2. it extracts to the directory the package-info names;
#   3. a consumer configures against the extracted tree alone (nvtx3, rmm, rapids_logger inside it);
#   4. three real gtest binaries from the build tree (CORE_TEST_NOCUDA, MATRIX_SELECT_TEST, UTILS_TEST)
#      run and pass with the extracted tree's lib/ first on LD_LIBRARY_PATH, and the libraries they
#      need (libraft-<variant>-<cuda>.so, librmm-<cuda>.so, librapids_logger-<cuda>.so) resolve to files
#      inside the extracted tree, not the build tree or a stock install.
# This is a smoke test, not the suite: tuned/full_test.sh already ran every binary against the build
# tree. What is new here is that the bits in the tarball are the ones running. Writes
# SMOKE_RESULTS_<variant>.log beside TEST_RESULTS; tuned/release.sh requires a passing log newer than
# the tarball.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -uo pipefail

GPU_TUNED_ARG_VARIANT="${1:?usage: tuned/smoke_test.sh <variant>}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1

# CMake 4 and Ninja from the toolkit's build venv: the installed package's CMake config files need CMake 4.0 and the host has 3.30.
gpu_tuned_setup_build_venv "${GPU_TUNED_VENV_DIR}" "${PROJECT_ROOT}" || exit 1

TOOLKIT_LIB_DIR="${GPU_TUNED_TOOLKIT_LIB_DIR:-${CUDA_HOME}/lib64}"
[[ -d "${TOOLKIT_LIB_DIR}" ]] || { echo "ERROR: toolkit lib dir ${TOOLKIT_LIB_DIR} not found." >&2; exit 1; }
RELEASES_DIR="$(gpu_tuned_out_dir releases "${PROJECT_ROOT}" "${CUDA_TAG}")"
DIST_DIR="$(gpu_tuned_out_dir dist "${PROJECT_ROOT}" "${CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
BUILD_DIR="$(gpu_tuned_out_dir build "${PROJECT_ROOT}" "${CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
INFO="${DIST_DIR}/package-info.txt"
LOG="${RELEASES_DIR}/SMOKE_RESULTS_${GPU_TUNED_VARIANT}.log"
[[ -f "${INFO}" ]] || { echo "ERROR: ${INFO} not found. Run tuned/package.sh ${GPU_TUNED_VARIANT} first." >&2; exit 1; }
info() { sed -n "s/^$1=//p" "${INFO}"; }
PKG_NAME="$(info pkg_name)"; TARBALL="${DIST_DIR}/$(info tarball)"; WANT_SHA="$(info sha256)"; RELEASE_TAG="$(info release_tag)"
[[ -f "${TARBALL}" ]] || { echo "ERROR: ${TARBALL} not found." >&2; exit 1; }
mkdir -p "${RELEASES_DIR}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
EXT="${WORK}/${PKG_NAME}"
FAILURES=0
fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }
ok() { echo "  ok:   $*"; }

run() {
    echo "raft package smoke test -- variant=${GPU_TUNED_VARIANT} cuda=${CUDA_TAG}"
    echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "release: ${RELEASE_TAG}"
    echo "tarball: $(basename "${TARBALL}")"
    echo ""

    got="$(sha256sum "${TARBALL}" | awk '{print $1}')"
    [[ "${got}" == "${WANT_SHA}" ]] && ok "sha256 matches package-info.txt (${got:0:12}...)" || fail "sha256 ${got} != package-info.txt ${WANT_SHA}"
    grep -q "^${got}  " "${RELEASES_DIR}/CHECKSUMS_${GPU_TUNED_VARIANT}" && ok "sha256 listed in CHECKSUMS_${GPU_TUNED_VARIANT}" || fail "sha256 not in CHECKSUMS_${GPU_TUNED_VARIANT}"

    tar -xjf "${TARBALL}" -C "${WORK}" || { fail "could not extract ${TARBALL}"; return; }
    [[ -d "${EXT}/lib" ]] && ok "extracts to ${PKG_NAME}/" || { fail "no ${PKG_NAME}/lib after extracting"; return; }

    gpu_tuned_verify_consumer_configure "${EXT}" rmm raft 2>&1 && ok "a consumer configures against the extracted package alone (nvtx3, rmm, rapids_logger inside it)" \
        || fail "consumer configure against the extracted package"

    export GPU_TUNED_SMOKE_LD_EXTRA="${TOOLKIT_LIB_DIR}"
    local t bin libs out
    for t in CORE_TEST_NOCUDA MATRIX_SELECT_TEST UTILS_TEST; do
        bin="${BUILD_DIR}/gtests/${t}"
        if [[ ! -x "${bin}" ]]; then fail "${t}: ${bin} not found (build the tests: tuned/build.sh with tests, then tuned/full_test.sh)"; continue; fi
        libs=("^librmm-${CUDA_TAG}\.so" "^librapids_logger-${CUDA_TAG}\.so")
        ldd "${bin}" | grep -q "libraft-${GPU_TUNED_VARIANT}-${CUDA_TAG}" && libs+=("^libraft-${GPU_TUNED_VARIANT}-${CUDA_TAG}\\.so")
        gpu_tuned_verify_resolves_in "${EXT}" "${bin}" "${libs[@]}" 2>&1 && ok "${t}: ${libs[*]} resolve inside the package" || fail "${t}: libraries do not resolve inside the package"
        out="$(LD_LIBRARY_PATH="${EXT}/lib:${TOOLKIT_LIB_DIR}" "${bin}" 2>&1)"; rc=$?
        if [[ ${rc} -eq 0 ]] && grep -q "^\[  PASSED  \]" <<< "${out}"; then
            ok "${t}: $(grep '^\[  PASSED  \]' <<< "${out}" | head -1 | sed 's/^\[  PASSED  \] //; s/\.$//'), $(grep -c '^\[  SKIPPED \]' <<< "${out}") skipped"
        else
            fail "${t}: exit ${rc}"; tail -15 <<< "${out}" | sed 's/^/        /'
        fi
    done
    echo "  complete: every check ran"
}

run 2>&1 | tee "${LOG}"
echo "" >> "${LOG}"
# A pass needs the positive evidence: run() reached its end ("complete:") and nothing failed. An abort
# inside run() (an unset variable, a failed extract) leaves no FAIL line, and must not read as a pass.
if grep -q '^  FAIL:' "${LOG}" || ! grep -q '^  complete: every check ran' "${LOG}"; then
    echo "=== Smoke test summary: FAILED ===" | tee -a "${LOG}"
    echo "finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${LOG}"
    exit 1
fi
echo "=== Smoke test summary: passed ===" | tee -a "${LOG}"
echo "finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${LOG}"
echo "Results written to ${LOG}"
