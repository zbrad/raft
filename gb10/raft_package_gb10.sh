#!/bin/bash
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="$(uname -m)"# shellcheck source=raft_env_gb10.sh
source "${PROJECT_ROOT}/gb10/raft_env_gb10.sh" || exit 1INSTALL_DIR="${PROJECT_ROOT}/cpp/build-${ARCH}/install"
PKG_NAME=raft-26.6-${ARCH}-cuda${CUDA_VERSION_COMPACT}
PKG_DIR=/tmp/${PKG_NAME}
OUT="${PROJECT_ROOT}/${PKG_NAME}.tar.bz2"

echo "Packaging ${PKG_NAME}..."
rm -rf ${PKG_DIR}
cp -r ${INSTALL_DIR} ${PKG_DIR}

cd /tmp
tar -cjf ${OUT} ${PKG_NAME}
echo "Created: ${OUT}"

SHA256=$(sha256sum ${OUT} | awk '{print $1}')
MD5=$(md5sum ${OUT} | awk '{print $1}')
SIZE=$(du -sh ${OUT} | awk '{print $1}')
FILES=$(find ${PKG_DIR} -type f | wc -l)

echo "SHA256: ${SHA256}"
echo "MD5:    ${MD5}"
echo "Size:   ${SIZE}"
echo "Files:  ${FILES}"

cat > "${PROJECT_ROOT}/CHECKSUMS_${ARCH}" <<EOF
${SHA256}  ${PKG_NAME}.tar.bz2
${MD5}  ${PKG_NAME}.tar.bz2
EOF

echo "Done."
