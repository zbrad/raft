#!/bin/bash
export PATH=~/.local/bin:/usr/local/cuda-13.2/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

gh release create v26.6.0-x86_64-cuda132 --repo zbrad/raft \
  "raft-26.6-x86_64-cuda132.tar.bz2#RAFT 26.6 x86_64 CUDA 13.2 binary package" \
  "CHECKSUMS_x86_64#CHECKSUMS_x86_64" \
  --title "RAFT 26.6 — x86_64 / CUDA 13.2 / SM_120" \
  --notes-file RELEASE_NOTES_26.6_x86_64.md \
  --target cu132
