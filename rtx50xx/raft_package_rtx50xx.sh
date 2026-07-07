#!/bin/bash
# raft_package_rtx50xx.sh — package the RTX 50xx C++ install tree as a tarball.
# New (split out of the old generic wsl/raft_package_wsl.sh, which had no
# per-GPU variant and hardcoded "cuda132" regardless of the toolkit actually
# used to build). Derives CUDA_VERSION_COMPACT from raft_env_rtx50xx.sh's
# auto-detection.
#
# NOTE: untested — run on an x86_64 host with RTX 50xx + CUDA installed.
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=raft_env_rtx50xx.sh
source "${PROJECT_ROOT}/rtx50xx/raft_env_rtx50xx.sh" || exit 1
INSTALL_DIR="${PROJECT_ROOT}/cpp/build-rtx50xx/install"
PKG_NAME="raft-26.6-x86_64-cuda${CUDA_VERSION_COMPACT}-rtx50xx"
PKG_DIR=/tmp/${PKG_NAME}
OUT="${PROJECT_ROOT}/${PKG_NAME}.tar.bz2"

echo "Packaging ${PKG_NAME}..."
rm -rf "${PKG_DIR}"
cp -r "${INSTALL_DIR}" "${PKG_DIR}"

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

cat > "${PROJECT_ROOT}/CHECKSUMS_rtx50xx" <<EOF
${SHA256}  ${PKG_NAME}.tar.bz2
${MD5}  ${PKG_NAME}.tar.bz2
EOF

echo "Done."
