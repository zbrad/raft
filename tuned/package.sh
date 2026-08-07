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
INSTALL_DIR="${PROJECT_ROOT}/cpp/build-${GPU_TUNED_VARIANT}/install"
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
SHORT_VER="$(echo "${VERSION}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"
# <short_ver>-<variant>-<cuda_tag>: variant-then-cuda_tag order now matches
# zbrad/cuvs's release-tag order (v${CUVS_VERSION}-${GPU_TUNED_VARIANT}-
# ${CUDA_TAG} there) -- this used to be <short_ver>-cuda<compact>-<variant>
# (cuda tag before variant), which didn't match cuvs's order despite both
# repos otherwise following the same scheme.
PKG_NAME="raft-${SHORT_VER}-${GPU_TUNED_VARIANT}-${CUDA_TAG}"
PKG_DIR="/tmp/${PKG_NAME}"
OUT="${PROJECT_ROOT}/${PKG_NAME}.tar.bz2"

echo "Packaging ${PKG_NAME}..."
rm -rf "${PKG_DIR}"
cp -r "${INSTALL_DIR}" "${PKG_DIR}"

# Stamp the tarball's own lib<RAFT_LIB_NAME>.so before archiving -- confirmed
# this was missing here: tuned/wheel.sh's embed_build_info call only ever
# touches its OWN renamed/staged copy (for the pip wheel), never this
# tarball's separate copy, so this whole distributable artifact had zero
# build-info stamp until now.
if [[ -f "${PKG_DIR}/lib/lib${RAFT_LIB_NAME}.so" ]]; then
    gpu_tuned_verify_arch "${PKG_DIR}/lib/lib${RAFT_LIB_NAME}.so" || exit 1
    embed_build_info "${PKG_DIR}/lib/lib${RAFT_LIB_NAME}.so" "${GPU_TUNED_VARIANT}" "${RAFT_LIB_NAME}" "${VERSION}+cu${CUDA_VERSION_COMPACT}" "${GPU_TUNED_HW_LABEL}"
fi

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

cat > "${PROJECT_ROOT}/tuned/releases/CHECKSUMS_${GPU_TUNED_VARIANT}" <<EOF
${SHA256}  ${PKG_NAME}.tar.bz2
${MD5}  ${PKG_NAME}.tar.bz2
EOF

echo "Done."
