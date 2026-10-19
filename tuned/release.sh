#!/bin/bash
# release.sh <variant> — the release gates for the C++ tarball tuned/package.sh made for the given GPU variant
# and CUDA toolkit. Shared implementation behind every gb10/rtx40/rtx50 raft_release_<variant>.sh wrapper. Same
# stage order as cuvs, faiss and llama.cpp:
#   tuned/build.sh -> tuned/full_test.sh -> tuned/package.sh -> tuned/smoke_test.sh
#   -> (review and commit tuned/releases/RELEASE_NOTES_<label>_<variant>_<cuda>.md) -> this -> tuned/publish.sh.
# It never publishes (no GitHub release is created here), never tags, never pushes, and never builds, tests or packages.
# If every gate passes it writes a ready-marker (tuned/build/<cuda>/releases/RELEASE_READY_<variant>) that
# tuned/publish.sh <variant> reads and publishes from. Any failure leaves no marker. docs/ARCHITECTURE.md
# (tuned-common) lists every gate below. The shared gates are gpu_tuned_release_gates in tuned/common.sh: tag
# label, clean tree, pushed HEAD, test log, tarball, smoke log, package-info, packaged commit, notes not DRAFT.
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
READY_MARKER="${RELEASES_DIR}/RELEASE_READY_${GPU_TUNED_VARIANT}"

FAILURES=0
fail() { echo "  FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }
ok() { echo "  ok:   $*"; }

# A new run starts from no marker, so a failing run can never leave an older pass behind.
gpu_tuned_release_marker_clear "${READY_MARKER}"

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

# Shared gates (tag label, clean tree, pushed HEAD, test log, tarball, smoke log, package-info, packaged commit,
# release notes).
gpu_tuned_release_gates \
  "tag=${RELEASE_TAG}" "variant=${GPU_TUNED_VARIANT}" "cuda=${CUDA_TAG}" "info=${INFO}" \
  "built=${BUILT_LIB}" "test_log=${TEST_RESULTS_FILE}" "test_pass=All binaries passed\." \
  "tarball=${TARBALL}" "smoke_log=${SMOKE_FILE}" "notes=${RELEASE_NOTES_FILE}" "packaged=${PACKAGED_COMMIT}" \
  || FAILURES=$((FAILURES + 1))

# Repo gate: the tarball's sha256 is listed in this variant's CHECKSUMS file.
if [[ ! -f "${TARBALL}" ]]; then
  fail "${TARBALL} not found"
else
  got="$(sha256sum "${TARBALL}" | awk '{print $1}')"
  if grep -q "^${got}  " "${RELEASES_DIR}/CHECKSUMS_${GPU_TUNED_VARIANT}" 2>/dev/null; then
    ok "tarball sha256 listed in CHECKSUMS_${GPU_TUNED_VARIANT}"
  else
    fail "tarball sha256 not listed in ${RELEASES_DIR}/CHECKSUMS_${GPU_TUNED_VARIANT}"
  fi
fi

if [[ ${FAILURES} -gt 0 ]]; then
  echo "" >&2
  echo "ERROR: ${FAILURES} gate(s) failed; no ready-marker written, nothing to publish." >&2
  exit 1
fi

gpu_tuned_release_ready "${READY_MARKER}" "zbrad/raft" "${RELEASE_TAG}" \
  "RAFT ${SHORT_VER} — ${RAFT_DEVICE_LABEL} / CUDA ${CUDA_VERSION} / SM_${GPU_TUNED_CUDA_ARCH} (${RELEASE_TAG#v})" \
  "${RELEASE_NOTES_FILE}" \
  "${TARBALL}#RAFT ${SHORT_VER} CUDA ${CUDA_VERSION} binary package (${RAFT_DEVICE_LABEL})" \
  "${TARBALL}.sha256#SHA-256 checksum" \
  "${RELEASES_DIR}/CHECKSUMS_${GPU_TUNED_VARIANT}#CHECKSUMS_${GPU_TUNED_VARIANT}" \
  "${TEST_RESULTS_FILE}#Full test suite results (${GPU_TUNED_VARIANT})" \
  "${SMOKE_FILE}#Package smoke test results (${GPU_TUNED_VARIANT})" || exit 1
