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
# <short_ver>-<variant>-<cuda_tag>: variant-then-cuda_tag order now matches
# zbrad/cuvs's release-tag order (v${CUVS_VERSION}-${GPU_TUNED_VARIANT}-
# ${CUDA_TAG} there) -- this used to be <short_ver>-cuda<compact>-<variant>
# (cuda tag before variant), which didn't match cuvs's order despite both
# repos otherwise following the same scheme.
#
# -g<short-sha> suffix: raft's own VERSION only bumps when upstream cuts
# a real release, so multiple genuinely different tuned-builds rebuilds
# (different commits, different content) can share the same SHORT_VER --
# confirmed 2026-09-08, had to delete-and-recreate v26.10-gb10-cu133 to
# republish today's build over the identical Aug 7 tag. The commit
# suffix makes every build's tag unique without inventing a synthetic
# sub-version number; `git log --oneline` off the short hash always
# tells you exactly what's in a given release. Must match release.sh's
# own identical computation -- independent, not passed between them,
# same pattern as SHORT_VER/RELEASE_NOTES_FILE above.
SHORT_SHA="$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD)"
PKG_NAME="raft-${SHORT_VER}-${GPU_TUNED_VARIANT}-${CUDA_TAG}-g${SHORT_SHA}"
PKG_DIR="/tmp/${PKG_NAME}"
# The tarball goes in the per-toolkit dist/ (it used to be written into the repo root).
OUT="${DIST_DIR}/${PKG_NAME}.tar.bz2"

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
    embed_build_info "${PKG_DIR}/lib/lib${RAFT_LIB_NAME}.so" "${GPU_TUNED_VARIANT}" "${RAFT_LIB_NAME}" "${VERSION}+cu${CUDA_VERSION_COMPACT}" "${GPU_TUNED_HW_LABEL}"
    # Confirm the stamp actually landed before archiving -- the tarball is
    # a straight `tar -cjf` of PKG_DIR below with no further build/install
    # pass, so this should always pass, but every other repo in this
    # fleet validates its stamp right after writing it rather than
    # assuming (embed_build_info's wrapper here pins the section name to
    # "raft_build_info" regardless of package -- see its definition).
    gpu_tuned_verify_build_info "${PKG_DIR}/lib/lib${RAFT_LIB_NAME}.so" "${RAFT_LIB_NAME}" "${VERSION}+cu${CUDA_VERSION_COMPACT}" "raft_build_info" || exit 1
fi

# Unique shared-object identities for the rapids chain this tree ships. librmm.so and
# librapids_logger.so carry the same file names and SONAMEs as stock RAPIDS, so a stock install (or an
# LD_LIBRARY_PATH pointing at one) could be loaded in place of ours, or ours in place of theirs. They
# become librmm-tuned.so / librapids_logger-tuned.so (file name, SONAME, every DT_NEEDED naming them),
# and the installed CMake import targets are repointed so consumers (zbrad/cuvs, faiss) link the tuned
# names. lib<RAFT_LIB_NAME>.so already carries variant and CUDA tag, so it is kept as is; libraft.a is
# an archive with no SONAME. See "unique shared-object identities" in tuned-common's tuned-common.sh.
echo ""
echo "Giving the rapids-chain shared objects unique identities:"
OURS_MANIFEST="$(mktemp)"
for so in librmm.so librapids_logger.so; do
    [[ -f "${PKG_DIR}/lib/${so}" ]] || { echo "ERROR: ${PKG_DIR}/lib/${so} is missing; the rename list is stale." >&2; exit 1; }
    echo "${so}" >> "${OURS_MANIFEST}"
done
KEEP_RE="^lib${RAFT_LIB_NAME}\\.so\$"
gpu_tuned_rename_sonames "${PKG_DIR}/lib" "${OURS_MANIFEST}" "${KEEP_RE}" | sed 's/^/  /'
rm -f "${OURS_MANIFEST}"
for so in librmm librapids_logger; do
    # cmake import files name the file and the SONAME; rewrite only those exact quoted/path forms
    grep -rlE "${so}\\.so" "${PKG_DIR}/lib/cmake" | while IFS= read -r cf; do
        sed -i -E "s#${so}\\.so#${so}${GPU_TUNED_SO_MARK}.so#g" "${cf}"
    done
done
# fail closed: every shared object is tuned or the kept raft lib, every DT_NEEDED resolves in the tree
# or is a toolkit/system library the target provides
gpu_tuned_verify_unique_sonames "${PKG_DIR}/lib" - "${KEEP_RE}" '^(linux-vdso\.so|ld-linux|libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so|libgcc_s\.so|libstdc\+\+\.so|libcuda\.so|libcudart\.so|libcublas\.so|libcublasLt\.so|libcusolver\.so|libcusparse\.so)' || exit 1
if grep -rE 'librmm\.so|librapids_logger\.so' "${PKG_DIR}/lib/cmake" >/dev/null; then
    echo "ERROR: CMake import files still name an unmarked librmm.so/librapids_logger.so." >&2
    exit 1
fi
# patchelf rewrote the files; the build-info stamp on the raft lib must have survived
gpu_tuned_verify_build_info "${PKG_DIR}/lib/lib${RAFT_LIB_NAME}.so" "${RAFT_LIB_NAME}" "${VERSION}+cu${CUDA_VERSION_COMPACT}" "raft_build_info" || exit 1

mkdir -p "${DIST_DIR}"
cd /tmp
tar -cjf "${OUT}" "${PKG_NAME}"
echo "Created: ${OUT}"

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

echo "Done."
