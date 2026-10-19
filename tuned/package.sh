#!/bin/bash
# package.sh <variant> — package the given GPU variant's C++
# install tree as a tarball. Shared implementation behind every
# gb10/rtx40/rtx50 raft_package_<variant>.sh wrapper.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GPU_TUNED_ARG_VARIANT="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1
# shellcheck source=raft_wheel_common.sh
source "${PROJECT_ROOT}/tuned/raft_wheel_common.sh" || exit 1
INSTALL_DIR="$(gpu_tuned_out_dir build "${PROJECT_ROOT}" "${CUDA_TAG}" "${GPU_TUNED_VARIANT}")/install"
RELEASES_DIR="$(gpu_tuned_out_dir releases "${PROJECT_ROOT}" "${CUDA_TAG}")"
DIST_DIR="$(gpu_tuned_out_dir dist "${PROJECT_ROOT}" "${CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
# Matches tuned/build.sh's RAFT_LIB_NAME (-DRAFT_OUTPUT_NAME=... baked into
# this build dir's CMakeCache at configure time) -- the installed .so is
# lib<this>.so, not the bare "libraft.so" upstream would otherwise produce.
RAFT_LIB_NAME="raft-${GPU_TUNED_VARIANT}-${CUDA_TAG}"
# tr -d '\r': defends against CRLF drift in VERSION, same as zbrad/cuvs's
# tuned/package.sh -- see that file's comment for the real failure mode
# this guards against (a hidden \r silently corrupting both the release
# tag and the tarball filename).
VERSION="$(tr -d '\r' < "${PROJECT_ROOT}/VERSION")"
# Derive short version (e.g. 26.08.00 -> 26.8) -- raft's own long-standing
# convention (older tags, RELEASE_NOTES_26.8_*.md), kept deliberately even
# though cuvs's own PKG_NAME/tag uses its full VERSION unshortened.
SHORT_VER="$(gpu_tuned_short_ver "${VERSION}")" || exit 1
# Release identity: the UTC date label (docs/ARCHITECTURE.md E2-E4), not the upstream version or a
# sha. The label is HEAD's UTC commit date plus the lowest unused sequence for that date among the
# repo's tags (gpu_tuned_allocate_date_label; GPU_TUNED_LABEL_SEQ=<n> chooses it offline). It is
# allocated once, here, and recorded in package-info.txt: release.sh reads it from there and never
# recomputes it. The upstream version (VERSION, SHORT_VER) is information for the title and notes.
# Releases published before 2026-10-15 are v<short_ver>-<variant>-<cuda_tag>-g<sha> and are not
# renamed; consumers accept both shapes and prefer a date-label tag.
rm -f "${DIST_DIR}/package-info.txt"
LABEL="$(gpu_tuned_allocate_date_label "${PROJECT_ROOT}")" || exit 1
RELEASE_TAG="$(gpu_tuned_native_tag "${GPU_TUNED_VARIANT}" "${CUDA_TAG}" "${LABEL}")" || exit 1
SHORT_SHA="$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD)"
PKG_NAME="raft-${RELEASE_TAG#v}"
PKG_DIR="/tmp/${PKG_NAME}"
# The tarball goes in the per-toolkit dist/ (it used to be written into the repo root).
OUT="${DIST_DIR}/${PKG_NAME}.tar.bz2"

# The install tree is what gets packaged, so it must come from the source at HEAD: the commit stamped
# into the build-tree lib when it was built (.raft_build_info "@ <sha>") may differ from HEAD only in tuned/
# (scripts, notes, docs), never in the library's source. A build tree left over from other source
# would otherwise be packaged and named for today.
BUILD_STAMP_LIB="$(gpu_tuned_out_dir build "${PROJECT_ROOT}" "${CUDA_TAG}" "${GPU_TUNED_VARIANT}")/lib${RAFT_LIB_NAME}.so"   # tuned/build.sh stamps this one; the installed copy may predate the stamp
[[ -f "${BUILD_STAMP_LIB}" ]] || { echo "ERROR: ${BUILD_STAMP_LIB} not found; run tuned/build.sh ${GPU_TUNED_VARIANT} for ${CUDA_TAG} first." >&2; exit 1; }
BUILD_COMMIT="$(readelf -p .raft_build_info "${BUILD_STAMP_LIB}" 2>/dev/null | sed -n 's/.* @ \([0-9a-f]\{7,40\}\),.*/\1/p' | head -1)"
[[ -n "${BUILD_COMMIT}" ]] || { echo "ERROR: ${BUILD_STAMP_LIB} carries no readable build commit (.raft_build_info)." >&2; exit 1; }
git -C "${PROJECT_ROOT}" cat-file -e "${BUILD_COMMIT}^{commit}" 2>/dev/null || { echo "ERROR: the library was built at ${BUILD_COMMIT}, which is not in this checkout." >&2; exit 1; }
STALE_SRC="$(git -C "${PROJECT_ROOT}" diff --name-only "${BUILD_COMMIT}" HEAD -- . ':!tuned' | head -5)"
if [[ -n "${STALE_SRC}" ]]; then
    echo "ERROR: the build was made at ${BUILD_COMMIT}, but source outside tuned/ changed since then:" >&2
    echo "${STALE_SRC}" | sed 's/^/    /' >&2
    echo "  Rebuild (tuned/build.sh ${GPU_TUNED_VARIANT}) and re-test before packaging." >&2
    exit 1
fi
echo "Install tree built at ${BUILD_COMMIT}; no source outside tuned/ changed since, packaging at ${SHORT_SHA}."

echo "Packaging ${PKG_NAME}..."
rm -rf "${PKG_DIR}"
cp -r "${INSTALL_DIR}" "${PKG_DIR}"

# Stamp the tarball's own lib<RAFT_LIB_NAME>.so before archiving -- confirmed
# this was missing here: tuned/wheel.sh's embed_build_info call only ever
# touches its OWN renamed/staged copy (for the pip wheel), never this
# tarball's separate copy, so this whole distributable artifact had zero
# build-info stamp until now.
if [[ -f "${PKG_DIR}/lib/lib${RAFT_LIB_NAME}.so" ]]; then
    gpu_tuned_verify_arch "${PKG_DIR}/lib/lib${RAFT_LIB_NAME}.so" "${GPU_TUNED_CUDA_ARCH}" || exit 1
    # The build-tree stamp (.raft_build_info, "@ <sha>") is the H6 anchor read above; it is internal and is
    # dropped from the shipped copy, which carries the JSON build info (.tuned_build_info) instead, verified.
    gpu_tuned_stamp_lib_json "${PKG_DIR}/lib/lib${RAFT_LIB_NAME}.so" raft "${RELEASE_TAG}" .raft_build_info || exit 1
fi

# Unique shared-object identities for the rapids chain this tree ships. librmm.so and
# librapids_logger.so carry the same file names and SONAMEs as stock RAPIDS, so a stock install (or an
# LD_LIBRARY_PATH pointing at one) could be loaded in place of ours, or ours in place of theirs. They
# are named librmm-<toolkit>.so / librapids_logger-<toolkit>.so (no device code: docs/ARCHITECTURE.md F1) by
# tuned/build.sh, with every DT_NEEDED naming them and the installed CMake import targets repointed so consumers
# (zbrad/cuvs, faiss) link those names. lib<RAFT_LIB_NAME>.so has device code and already carries
# -<variant>-<toolkit>; libraft.a is an archive with no SONAME. The manifest below records the mark each
# takes, chosen from the library's contents; the rename is a no-op on a tree the build already named, and renames
# a stock-named file from an older install tree.
echo ""
echo "Checking the rapids-chain shared objects' identities:"
OURS_MANIFEST="$(mktemp)"
gpu_tuned_axes_manifest "${PKG_DIR}/lib" "${GPU_TUNED_VARIANT}" "${CUDA_TAG}" "${OURS_MANIFEST}" librmm.so librapids_logger.so || { rm -f "${OURS_MANIFEST}"; exit 1; }
KEEP_RE="^lib${RAFT_LIB_NAME}\\.so\$"
# Renames, repoints the installed CMake import files, then fails closed: every shared object is
# renamed or the kept raft lib, every DT_NEEDED resolves in the tree or is a toolkit/system library.
gpu_tuned_rename_package "${PKG_DIR}/lib" "${OURS_MANIFEST}" - "${KEEP_RE}" \
    '^(linux-vdso\.so|ld-linux|libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so|libgcc_s\.so|libstdc\+\+\.so|libcuda\.so|libcudart\.so|libcublas\.so|libcublasLt\.so|libcusolver\.so|libcusparse\.so)' \
    "${PKG_DIR}/lib/cmake" "${PKG_DIR}/lib/pkgconfig" || { rm -f "${OURS_MANIFEST}"; exit 1; }
rm -f "${OURS_MANIFEST}"
# F1: each shared object (the raft lib included) carries the mark its contents require
gpu_tuned_verify_so_axes "${PKG_DIR}/lib" "${GPU_TUNED_VARIANT}" "${CUDA_TAG}" - || exit 1
# patchelf rewrote the files; the build-info stamp on the raft lib must have survived
gpu_tuned_verify_build_info_json "${PKG_DIR}/lib/lib${RAFT_LIB_NAME}.so" "release=${RELEASE_TAG}" "variant=${GPU_TUNED_VARIANT}" "cuda.tag=${CUDA_TAG}" || exit 1

# Self-containment gates. A package whose installed CMake files ask for nvtx3 must ship it (config and
# headers): found in a pip wheel instead of fetched, it is silently left out and consumers (faiss) fail
# to configure. Then prove it the way a consumer would: configure a minimal project against this
# package alone and require nvtx3, rmm and rapids_logger to resolve inside it.
if grep -rqE 'find_dependency\(nvtx3' "${PKG_DIR}/lib/cmake" 2>/dev/null; then
    if ! compgen -G "${PKG_DIR}/lib*/cmake/nvtx3/nvtx3-config.cmake" >/dev/null || [[ ! -f "${PKG_DIR}/include/nvtx3/nvtx3.hpp" ]]; then
        echo "ERROR: ${PKG_NAME}'s CMake files require nvtx3 but the package does not ship its config and headers; it was found outside the build (a pip wheel?) instead of fetched. That copy is not the tuned, tested one." >&2
        exit 1
    fi
fi
gpu_tuned_verify_consumer_configure "${PKG_DIR}" rmm raft || exit 1

mkdir -p "${DIST_DIR}"
cd /tmp
tar -cjf "${OUT}" "${PKG_NAME}"
echo "Created: ${OUT}"

# sha256sum-format sidecar, attached to the release so a consumer can verify the download.
gpu_tuned_write_sha256_sidecar "${OUT}" || exit 1

SHA256=$(sha256sum "${OUT}" | awk '{print $1}')
MD5=$(md5sum "${OUT}" | awk '{print $1}')
SIZE=$(du -sh "${OUT}" | awk '{print $1}')
FILES=$(find "${PKG_DIR}" -type f | wc -l)

echo "SHA256: ${SHA256}"
echo "MD5:    ${MD5}"
echo "Size:   ${SIZE}"
echo "Files:  ${FILES}"

mkdir -p "${RELEASES_DIR}"
cat > "${RELEASES_DIR}/CHECKSUMS_${GPU_TUNED_VARIANT}" <<EOF
${SHA256}  ${PKG_NAME}.tar.bz2
${MD5}  ${PKG_NAME}.tar.bz2
EOF

# Written last: its presence means the package passed every gate above. release.sh requires it.
cat > "${DIST_DIR}/package-info.txt" <<INFO
release_tag=${RELEASE_TAG}
pkg_name=${PKG_NAME}
tarball=${PKG_NAME}.tar.bz2
upstream_version=${VERSION}
commit=${SHORT_SHA}
build_commit=${BUILD_COMMIT}
cuda_tag=${CUDA_TAG}
variant=${GPU_TUNED_VARIANT}
sha256=${SHA256}
INFO

# DRAFT release notes (docs/ARCHITECTURE.md H5): the file release.sh expects, written only when it does not exist yet and
# never over an existing one. The banner line is what the author deletes after reviewing the draft and committing it.
NOTES_FILE="${PROJECT_ROOT}/tuned/releases/RELEASE_NOTES_${RELEASE_TAG#v}.md"
if [[ -e "${NOTES_FILE}" ]]; then
    echo "Release notes ${NOTES_FILE#"${PROJECT_ROOT}"/} already exist; not overwritten."
else
    TEST_LOG="${RELEASES_DIR}/TEST_RESULTS_${GPU_TUNED_VARIANT}.log"
    TEST_SUMMARY="$(grep -a 'Full test suite summary' "${TEST_LOG}" 2>/dev/null | tail -1 | sed 's/^=* *//; s/ *=*$//' || true)"
    cat > "${NOTES_FILE}" <<NOTES
<!-- DRAFT — not yet published: review, then delete this line and commit -->
# RAFT ${VERSION} — GB10 / DGX Spark (CUDA ${CUDA_VERSION}) — ${RELEASE_TAG}

**Package**: \`${PKG_NAME}.tar.bz2\`, built at \`${BUILD_COMMIT}\`

Describe what changed in this release here.

## Tested

- ${TEST_SUMMARY:-No full test log at ${TEST_LOG}; run tuned/full_test.sh ${GPU_TUNED_VARIANT} first.}
NOTES
    echo "Wrote DRAFT release notes: ${NOTES_FILE#"${PROJECT_ROOT}"/}"
fi

echo "Packaged ${RELEASE_TAG}. Next: tuned/smoke_test.sh ${GPU_TUNED_VARIANT}, then tuned/release.sh ${GPU_TUNED_VARIANT}."
echo "Done."
