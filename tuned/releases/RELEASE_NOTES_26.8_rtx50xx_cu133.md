# RAFT 26.8 — RTX 50xx Release Notes

**Release Date**: 2026-07-27
**Package**: `raft-26.8-x86_64-cuda133-rtx50xx.tar.bz2`
**Wheels**: `libraft-rtx50xx-cu13`, `pylibraft-rtx50xx-cu13`, `raft-dask-rtx50xx-cu13` (+ bundled `librmm-cu13`/`rmm-cu13`)
**Platform**: x86_64
**GPU Architecture**: SM_120a (RTX 50xx / Blackwell, consumer)

## Overview

RAFT 26.8 for RTX 50xx is a single-arch "tuned" build targeting exactly
SM_120a — this is the first real, published release for this variant
(previous work on it was build/test verification only, never published).

## Arch correction: SM_120 → SM_120a

Earlier tuned-build tooling for this variant targeted bare `sm_120`,
under the assumption that RTX 50xx (consumer Blackwell) exposes no
family-specific accelerated ISA extension, unlike datacenter-class
Blackwell chips. That assumption was wrong: `sm_120a` is a real,
NVIDIA-documented target for RTX 5090/5080/5070/etc., exposing
accelerated tensor-core instructions (e.g. FP4 support) not available
under bare `sm_120`. This release corrects `tuned/devices/rtx50xx.conf`
to target `sm_120a` and rebuilds from that corrected value —
`gpu_tuned_verify_arch` confirms the shipped `.so` is `sm_120a`, not
`sm_120`.

## Build Environment

### CUDA Requirements
| Component | Version |
|-----------|---------|
| **CUDA Toolkit** | 13.3 |
| **RMM** | 26.10.00 (CPM-fetched at raft's own C++ configure time) |

### Compiler & Tools
| Component | Version |
|-----------|---------|
| **GCC** | 13.3.0 |
| **CMake** | 4.4.0 |
| **Python** | 3.14 |

## Supported Hardware

### Verified
- **NVIDIA Blackwell Architecture (consumer)**
  - Compute Capability: SM_120a
  - RTX 5090 / RTX 5080 / RTX 5070 / RTX 5060 (all share SM_120a; only
    core/memory counts differ)

### Compatible
- Other x86_64 systems with an RTX 50-series GPU and CUDA 13.x

## Package Contents

### Shared Libraries (lib/)
- `libraft.so` — RAFT runtime library, built for SM_120a
- `librmm.so` — RAPIDS Memory Manager (CPM-fetched by raft's own build)
- `librapids_logger.so` — Logging utilities

### Headers (include/)
- `raft/`, `raft_runtime/`, `rmm/`, `rapids_logger/`, `rapids/`, `nvtx3/`

### CMake Configuration (lib/cmake/)
- RAFT CMake targets and configuration files (`raft-config.cmake`,
  `raft-targets.cmake`, etc.) and RMM's own exported config — this is
  the full install tree, including the CMake package-config files a
  downstream from-source consumer (e.g. cuvs) needs to `find_package(raft)`
  against this artifact instead of rebuilding raft itself.

## Installation

### Extract the Package
```bash
tar -xjf raft-26.8-x86_64-cuda133-rtx50xx.tar.bz2
cd raft-26.8-x86_64-cuda133-rtx50xx
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
  -DCMAKE_PREFIX_PATH=/path/to/raft-26.8-x86_64-cuda133-rtx50xx \
  -DCMAKE_CXX_STANDARD=20 \
  -DCMAKE_CUDA_STANDARD=20 \
  -DCMAKE_CUDA_ARCHITECTURES=120a \
  ..
make -j$(nproc)
```

### Install via wheels instead
```bash
pip install libraft-rtx50xx-cu13 pylibraft-rtx50xx-cu13 raft-dask-rtx50xx-cu13
```

## Compatibility

### API Stability
- **C++ API**: Stable, matches raft's own 26.08.00 release
- **CMake Targets**: Stable
- **Binary Compatibility**: `libraft.so` is a new build targeting a
  different arch (`sm_120a` vs. a hypothetical prior `sm_120` build) —
  recompile downstream projects against this artifact.

### Verify Integrity
```bash
sha256sum -c CHECKSUMS_rtx50xx
```

---

**RAFT Version**: 26.8
**Release Date**: 2026-07-27
**Package**: raft-26.8-x86_64-cuda133-rtx50xx.tar.bz2
**Platform**: x86_64 / SM_120a / CUDA 13.3
