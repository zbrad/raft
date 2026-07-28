#!/bin/bash
# package.sh <variant> — package the given GPU variant's C++
# install tree as a tarball. Shared implementation behind every
# gb10/rtx40xx/rtx50xx raft_package_<variant>.sh wrapper.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GPU_TUNED_ARG_VARIANT="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1
# shellcheck source=raft_wheel_common.sh
source "${PROJECT_ROOT}/tuned/raft_wheel_common.sh" || exit 1
INSTALL_DIR="${PROJECT_ROOT}/cpp/build-${GPU_TUNED_VARIANT}/install"
VERSION="$(cat "${PROJECT_ROOT}/VERSION")"
# Derive short version (e.g. 26.06.00 -> 26.6)
SHORT_VER="$(echo "${VERSION}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"
PKG_NAME="raft-${SHORT_VER}-${GPU_TUNED_PLATFORM}-cuda${CUDA_VERSION_COMPACT}-${GPU_TUNED_VARIANT}"
PKG_DIR="/tmp/${PKG_NAME}"
OUT="${PROJECT_ROOT}/${PKG_NAME}.tar.bz2"

echo "Packaging ${PKG_NAME}..."
rm -rf "${PKG_DIR}"
cp -r "${INSTALL_DIR}" "${PKG_DIR}"

# Stamp the tarball's own libraft.so before archiving -- confirmed this
# was missing here: tuned/wheel.sh's embed_build_info call only ever
# touches its OWN renamed/staged copy of libraft.so (for the pip wheel),
# never this tarball's separate copy, so this whole distributable
# artifact had zero build-info stamp until now.
if [[ -f "${PKG_DIR}/lib/libraft.so" ]]; then
    gpu_tuned_verify_arch "${PKG_DIR}/lib/libraft.so" || exit 1
    embed_build_info "${PKG_DIR}/lib/libraft.so" "${GPU_TUNED_VARIANT}" "libraft" "${VERSION}+cu${CUDA_VERSION_COMPACT}" "${GPU_TUNED_HW_LABEL}"
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
