#!/bin/bash
# release.sh <variant> — publish the C++ tarball tuned/package.sh made for the given GPU variant and
# CUDA toolkit as a GitHub release. Shared implementation behind every gb10/rtx40/rtx50
# raft_release_<variant>.sh wrapper. Same stage order as cuvs, faiss and llama.cpp:
#   tuned/build.sh -> tuned/full_test.sh -> tuned/package.sh -> tuned/smoke_test.sh
#   -> (review and commit tuned/releases/RELEASE_NOTES_<label>_<variant>_<cuda>.md) -> this.
# It never builds, tests or packages. docs/ARCHITECTURE.md (tuned-common) lists every gate below.
#
# The release is named by the date label package.sh allocated (the native tag
# v0.<YYYYMMDD>.<seq>-<variant>-<cuda>), read from package-info.txt: never recomputed here, because
# the notes commit moves HEAD and its date. The upstream version only appears in the title.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GPU_TUNED_ARG_VARIANT="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1
cd "${PROJECT_ROOT}"

RELEASES_DIR="$(gpu_tuned_out_dir releases "${PROJECT_ROOT}" "${CUDA_TAG}")"
DIST_DIR="$(gpu_tuned_out_dir dist "${PROJECT_ROOT}" "${CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
INFO="${DIST_DIR}/package-info.txt"
TEST_RESULTS_FILE="${RELEASES_DIR}/TEST_RESULTS_${GPU_TUNED_VARIANT}.log"
SMOKE_FILE="${RELEASES_DIR}/SMOKE_RESULTS_${GPU_TUNED_VARIANT}.log"
BUILT_LIB="$(gpu_tuned_out_dir build "${PROJECT_ROOT}" "${CUDA_TAG}" "${GPU_TUNED_VARIANT}")/lib${RAFT_LIB_NAME:-raft-${GPU_TUNED_VARIANT}-${CUDA_TAG}}.so"

FAILURES=0
fail() { echo "  FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }
ok() { echo "  ok:   $*"; }

if [[ ! -f "${INFO}" ]]; then
  echo "ERROR: ${INFO} not found -- run tuned/package.sh ${GPU_TUNED_VARIANT} at the commit being released first." >&2
  exit 1
fi
info() { sed -n "s/^$1=//p" "${INFO}"; }
RELEASE_TAG="$(info release_tag)"; PKG_NAME="$(info pkg_name)"; TARBALL="${DIST_DIR}/$(info tarball)"
UPSTREAM_VERSION="$(info upstream_version)"; PACKAGED_COMMIT="$(info commit)"
SHORT_VER="$(gpu_tuned_short_ver "${UPSTREAM_VERSION}")" || exit 1
RELEASE_NOTES_FILE="tuned/releases/RELEASE_NOTES_${RELEASE_TAG#v}.md"

echo "Release ${RELEASE_TAG} (RAFT ${SHORT_VER}, packaged at ${PACKAGED_COMMIT}):"

# Tag shape: a date label, checked here and again by gpu_tuned_publish_release.
gpu_tuned_check_release_tag "${RELEASE_TAG}" && ok "tag carries a date label" || fail "tag ${RELEASE_TAG} carries no date label"

# Test gate: a fresh, passing full-test run. "Fresh" = newer than the built .so, not just present.
if [[ ! -f "${TEST_RESULTS_FILE}" ]]; then
  fail "${TEST_RESULTS_FILE} not found -- run tuned/full_test.sh ${GPU_TUNED_VARIANT}"
elif [[ -f "${BUILT_LIB}" && "${BUILT_LIB}" -nt "${TEST_RESULTS_FILE}" ]]; then
  fail "${BUILT_LIB} is newer than ${TEST_RESULTS_FILE}: the test results predate the build; re-run tuned/full_test.sh"
elif ! grep -q "All binaries passed\." "${TEST_RESULTS_FILE}"; then
  fail "${TEST_RESULTS_FILE} does not show a clean pass"
else
  ok "full test suite passed, log newer than the built library"
fi

# Package gate: the tarball matches package-info.txt and CHECKSUMS, was made after the tests, and a
# passing smoke test of THIS tarball is newer than it.
if [[ ! -f "${TARBALL}" ]]; then
  fail "${TARBALL} not found"
else
  got="$(sha256sum "${TARBALL}" | awk '{print $1}')"
  if [[ "${got}" == "$(info sha256)" ]] && grep -q "^${got}  " "${RELEASES_DIR}/CHECKSUMS_${GPU_TUNED_VARIANT}"; then
    ok "tarball sha256 matches package-info.txt and CHECKSUMS_${GPU_TUNED_VARIANT}"
  else
    fail "tarball sha256 does not match package-info.txt / CHECKSUMS"
  fi
  SHA_FILE="${TARBALL}.sha256"
  if [[ ! -f "${SHA_FILE}" ]]; then
    fail "${SHA_FILE} not found -- package again (package.sh writes the sha256 sidecar)"
  elif (cd "$(dirname "${TARBALL}")" && sha256sum -c --quiet "$(basename "${SHA_FILE}")") >/dev/null 2>&1; then
    ok "sha256 sidecar matches the tarball"
  else
    fail "sha256 sidecar does not match the tarball"
  fi
  if [[ -f "${TEST_RESULTS_FILE}" && "${TEST_RESULTS_FILE}" -nt "${TARBALL}" ]]; then
    fail "the test log is newer than the tarball; package again after testing"
  else
    ok "tarball was made after the tests"
  fi
  if [[ ! -f "${SMOKE_FILE}" ]]; then
    fail "${SMOKE_FILE} not found -- run tuned/smoke_test.sh ${GPU_TUNED_VARIANT}"
  elif [[ "${TARBALL}" -nt "${SMOKE_FILE}" ]]; then
    fail "${TARBALL} is newer than the smoke test log; re-run tuned/smoke_test.sh ${GPU_TUNED_VARIANT}"
  elif ! grep -q "Smoke test summary: passed" "${SMOKE_FILE}"; then
    fail "${SMOKE_FILE} does not show a pass"
  else
    ok "smoke test of this tarball passed"
  fi
fi
if ! { grep -qxF "cuda_tag=${CUDA_TAG}" "${INFO}" && grep -qxF "variant=${GPU_TUNED_VARIANT}" "${INFO}"; }; then
  fail "package-info.txt is for another toolkit or variant"
fi

# Only the release notes may change between the packaged commit and HEAD.
changed="$(git diff --name-only "${PACKAGED_COMMIT}" HEAD -- . ':!tuned/releases' 2>/dev/null || echo '?')"
if [[ -z "${changed}" ]]; then
  ok "only release notes changed since the packaged commit ${PACKAGED_COMMIT}"
else
  fail "files other than tuned/releases/ changed since the packaged commit ${PACKAGED_COMMIT}: $(echo "${changed}" | head -3 | tr '\n' ' ')"
fi

# Release notes: a tracked, reviewed file.
if [[ ! -f "${RELEASE_NOTES_FILE}" ]]; then
  fail "${RELEASE_NOTES_FILE} not found"
elif grep -q 'DRAFT — not yet published' "${RELEASE_NOTES_FILE}"; then
  fail "${RELEASE_NOTES_FILE} is still a draft (DRAFT banner present)"
elif ! git ls-files --error-unmatch "${RELEASE_NOTES_FILE}" >/dev/null 2>&1; then
  fail "${RELEASE_NOTES_FILE} is not committed"
else
  ok "release notes ${RELEASE_NOTES_FILE##*/} committed"
fi

if [[ ${FAILURES} -gt 0 ]]; then
  echo "" >&2
  echo "ERROR: ${FAILURES} gate(s) failed; nothing was published." >&2
  exit 1
fi

gpu_tuned_publish_release "zbrad/raft" "${RELEASE_TAG}" \
  "RAFT ${SHORT_VER} — ${RAFT_DEVICE_LABEL} / CUDA ${CUDA_VERSION} / SM_${GPU_TUNED_CUDA_ARCH} (${RELEASE_TAG#v})" \
  "@${RELEASE_NOTES_FILE}" \
  "${TARBALL}#RAFT ${SHORT_VER} CUDA ${CUDA_VERSION} binary package (${RAFT_DEVICE_LABEL})" \
  "${SHA_FILE}#SHA-256 checksum" \
  "${RELEASES_DIR}/CHECKSUMS_${GPU_TUNED_VARIANT}#CHECKSUMS_${GPU_TUNED_VARIANT}" \
  "${TEST_RESULTS_FILE}#Full test suite results (${GPU_TUNED_VARIANT})" \
  "${SMOKE_FILE}#Package smoke test results (${GPU_TUNED_VARIANT})"
