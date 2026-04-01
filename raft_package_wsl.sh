#!/bin/bash
export PATH=/home/zbrad/.local/bin:/usr/local/cuda-13.2/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

INSTALL_DIR=/mnt/f/GitHub/raft/cpp/build/install
PKG_NAME=raft-26.6-x86_64-cuda132
PKG_DIR=/tmp/${PKG_NAME}
OUT=/mnt/f/GitHub/raft/${PKG_NAME}.tar.bz2

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

# Write checksums
cat > /mnt/f/GitHub/raft/CHECKSUMS_x86_64 <<EOF
${SHA256}  ${PKG_NAME}.tar.bz2
${MD5}  ${PKG_NAME}.tar.bz2
EOF

echo "Done."
