# RAFT 26.8 — GB10 / DGX Spark Release Notes

**Release Date**: 2026-08-05
**Package**: `raft-26.8-aarch64-cuda133-gb10.tar.bz2`
**Platform**: aarch64
**GPU Architecture**: SM_121a (GB10 / DGX Spark, Grace Blackwell)

## Overview

This is the first published C++ tarball release for GB10 built through the
consolidated `tuned/build.sh` → `tuned/package.sh` → `tuned/release.sh`
pipeline (the same pipeline already used for rtx40 and rtx50). GB10
previously only had a wheels release
([`v26.08.00-aarch64-cuda133-gb10`](https://github.com/zbrad/raft/releases/tag/v26.08.00-aarch64-cuda133-gb10),
2026-07-07) — this adds the C++ install-tree tarball (headers + shared
libraries + CMake package config) that downstream from-source consumers
(e.g. `zbrad/cuvs`) link against, matching what rtx40/rtx50 already
publish.

No architecture correction was needed for this release: unlike rtx50
(which was rebuilt this cycle after discovering it had shipped on bare
`sm_120` instead of `sm_120a`), GB10's `tuned/devices/gb10.conf` has
targeted `sm_121a` all along — confirmed again here via `cuobjdump`
against this build's `libraft.so` (`sm_121a` cubins, not `sm_121`).

## What's New in the Publish Pipeline

Since GB10's last release, the shared `tuned/` tooling picked up:

- **Build-info stamping on the tarball itself, not just the wheel**
  (previously `tuned/wheel.sh`'s `embed_build_info` only ever stamped its
  own staged copy for the pip wheel; `tuned/package.sh`'s separate tarball
  copy shipped with no stamp at all). This tarball's `libraft.so` now
  carries variant, version, hardware label, and build timestamp in a
  dedicated ELF section.
- **`--target tuned-builds` fix** in the release-publish scripts — they
  had hardcoded the old `native-builds` branch name (renamed
  `native-builds` → `deprecated-native-builds` → `tuned-builds` earlier
  this cycle), which broke publishing outright until fixed.
- **`tuned/` relocation** — all fork-specific build/release tooling moved
  from repo-root clutter (`gb10/`, `rtx40/`, `rtx50/`, `gpu_tuned/`,
  loose `raft_*.sh` helpers) into a single `tuned/` subtree, keeping the
  repo root aligned with upstream `rapidsai/raft`'s layout.

No `cpp/` source changes landed for GB10 in this cycle — this release is
tooling/publish-pipeline maturity, not an algorithm or bug-fix release.

## Build Environment

### CUDA Requirements
| Component | Version |
|-----------|---------|
| **CUDA Toolkit** | 13.3 |
| **RMM** | 26.10.00 (CPM-fetched at raft's own C++ configure time) |

### Compiler & Tools
| Component | Version |
|-----------|---------|
| **GCC** | 14.2.0 |
| **CMake** | 4.3.1 |
| **Python** | 3.14.6 |

## Supported Hardware

### Verified
- **NVIDIA Grace Blackwell (GB10)**
  - Compute Capability: SM_121a
  - DGX Spark (aarch64, Grace CPU + GB10 GPU)

### Compatible
- Other aarch64 systems with a GB10-class GPU and CUDA 13.x

## Package Contents

### Shared Libraries (lib/)
- `libraft.so` — RAFT runtime library, built for SM_121a
- `librmm.so` — RAPIDS Memory Manager (CPM-fetched by raft's own build)
- `librapids_logger.so` — Logging utilities

### Headers (include/)
- `raft/`, `raft_runtime/`, `rmm/`, `rapids_logger/`, `rapids/`, `nvtx3/`

### CMake Configuration (lib/cmake/)
- RAFT CMake targets and configuration files (`raft-config.cmake`,
  `raft-targets.cmake`, etc.) and RMM's own exported config — the full
  install tree a downstream from-source consumer (e.g. cuvs) needs to
  `find_package(raft)` against this artifact instead of rebuilding raft
  itself.

## Installation

### Extract the Package
```bash
tar -xjf raft-26.8-aarch64-cuda133-gb10.tar.bz2
cd raft-26.8-aarch64-cuda133-gb10
```

### Set Up Environment
```bash
export RAFT_ROOT="$(pwd)"
export LD_LIBRARY_PATH="${RAFT_ROOT}/lib:${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}"
export CMAKE_PREFIX_PATH="${RAFT_ROOT}:${CMAKE_PREFIX_PATH}"
```

### Use in CMake Project
```cmake
cmake_minimum_required(VERSION 3.30.4 LANGUAGES CXX CUDA)
project(MyProject LANGUAGES CXX CUDA)

find_package(raft REQUIRED)
target_link_libraries(my_target PRIVATE raft::raft)
```

### Compile
```bash
mkdir build && cd build
cmake \
  -DCMAKE_PREFIX_PATH=/path/to/raft-26.8-aarch64-cuda133-gb10 \
  -DCMAKE_CXX_STANDARD=20 \
  -DCMAKE_CUDA_STANDARD=20 \
  -DCMAKE_CUDA_ARCHITECTURES=121a \
  ..
make -j$(nproc)
```

### Install via wheels instead
The `libraft-cu13`/`pylibraft-spark-cu13` wheels for GB10 are published
separately — see
[`v26.08.00-aarch64-cuda133-gb10`](https://github.com/zbrad/raft/releases/tag/v26.08.00-aarch64-cuda133-gb10).

## Compatibility

### API Stability
- **C++ API**: Stable, matches raft's own 26.08.00 release (no `cpp/`
  changes this cycle)
- **CMake Targets**: Stable
- **Binary Compatibility**: New build; recompile downstream projects
  against this artifact rather than relying on binary compatibility with
  the July 7 wheels-only release.

### Verify Integrity
```bash
sha256sum -c CHECKSUMS_gb10
```

---

**RAFT Version**: 26.8
**Release Date**: 2026-08-05
**Package**: raft-26.8-aarch64-cuda133-gb10.tar.bz2
**Platform**: aarch64 / SM_121a / CUDA 13.3
