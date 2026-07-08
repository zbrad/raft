#!/bin/bash
# raft_package_rtx40xx.sh — package the RTX 40xx C++ install tree as a tarball.
# Renamed/fixed from wsl/raft_package_wsl.sh, which hardcoded "cuda132" in the
# package name regardless of the toolkit actually used to build. Now derives
# CUDA_VERSION_COMPACT from raft_env_rtx40xx.sh's auto-detection.
#
# NOTE: untested — run on an x86_64 host with RTX 40xx + CUDA installed.
export PATH=~/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=raft_env_rtx40xx.sh
source "${PROJECT_ROOT}/rtx40xx/raft_env_rtx40xx.sh" || exit 1
INSTALL_DIR="${PROJECT_ROOT}/cpp/build-rtx40xx/install"
VERSION="$(cat "${PROJECT_ROOT}/VERSION")"
# Derive short version (e.g. 26.06.00 -> 26.6)
SHORT_VER="$(echo "${VERSION}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"
PKG_NAME="raft-${SHORT_VER}-x86_64-cuda${CUDA_VERSION_COMPACT}-rtx40xx"
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

cat > "${PROJECT_ROOT}/CHECKSUMS_rtx40xx" <<EOF
${SHA256}  ${PKG_NAME}.tar.bz2
${MD5}  ${PKG_NAME}.tar.bz2
EOF

echo "Done."
