# RAFT 26.10 — GB10 / DGX Spark Release Notes

**Release Date**: 2026-08-07
**Package**: `raft-26.10-gb10-cu133.tar.bz2`
**Platform**: aarch64
**GPU Architecture**: SM_121a (GB10 / DGX Spark, Grace Blackwell)

## Overview

Follow-up to the [26.8 gb10 release](https://github.com/zbrad/raft/releases/tag/v26.8-gb10-cu133)
(published 2026-08-07, superseded by this one), picking up real upstream
`rapidsai/raft` changes that landed between raft's `26.08.00` and
`26.10.00` versions. `VERSION` bumped to `26.10.00` as a side effect of
merging `origin/tuned-builds` (which itself periodically merges upstream
`main`) — this release rebuilds against that merge rather than leaving
the published gb10 artifact one version behind the checked-out source.

No formal changelog exists yet for 26.08/26.10 (`CHANGELOG.md`'s newest
entry is still `26.06.00`) — the following is compiled directly from
`git log` between the two version points.

## What Changed Upstream (26.08.00 → 26.10.00)

Real functional changes:
- **Native row-major PCA** ([#3036](https://github.com/rapidsai/raft/pull/3036))
  — PCA now supports row-major layout natively.
- **Predictable `raft::resources`** ([#3052](https://github.com/rapidsai/raft/pull/3052))
  — resource-management rework (same PR already backported into the
  aarch64/26.6 line's earlier work).
- **Fix missing nvtx stack and host mem resource by exporting the symbols**
  ([#3083](https://github.com/rapidsai/raft/pull/3083)) — real
  export/symbol-visibility bug fix.
- **Remove orphaned `raft::runtime::matrix::select_k` declaration**
  ([#3084](https://github.com/rapidsai/raft/pull/3084)) — dead API
  removal.
- **Make cuBLASLt descriptor wrappers move-safe**
  ([#3078](https://github.com/rapidsai/raft/pull/3078)).
- **Use `cuda::std::numeric_limits` in LAP kernels instead of passing
  infinity** ([#3094](https://github.com/rapidsai/raft/pull/3094)) and
  **use `cuda::std::bit_cast` in stats minmax instead of a hand-rolled
  helper** ([#3095](https://github.com/rapidsai/raft/pull/3095)) —
  internal cleanups, standard-library adoption.
- **Mitigate cuBLASLt 13.6 GEMM bug for inputs greater than 2^31**
  ([#3098](https://github.com/rapidsai/raft/pull/3098)) and **cublas team
  verified workaround for large GEMM `algo68` bug**
  ([#3100](https://github.com/rapidsai/raft/pull/3100)) — two real
  CUDA-13.6-specific GEMM correctness fixes.
- **wheels: build CUDA 13 wheels with latest CTK (13.3.0)**
  ([#3076](https://github.com/rapidsai/raft/pull/3076)) — build-only,
  matches the CUDA 13.3 toolkit this gb10 build already uses.

Housekeeping only (pre-commit/SPDX/docs-theme cleanup, the version-bump
commit itself) is omitted above.

## What's New in the Publish Pipeline (carried over from 26.8)

- Variant-qualified library naming: `libraft-gb10-cu133.so` (via a new
  `RAFT_OUTPUT_NAME` CMake override), matching `zbrad/cuvs`'s own
  `libcuvs-<variant>-<cuda_tag>.so` convention.
- Release tag convention unified with cuvs:
  `v<short_ver>-<variant>-<cuda_tag>` (this release: `v26.10-gb10-cu133`).
- Build-info stamping on the tarball's own `.so`, not just the wheel's.
- `zbrad/cuvs`'s `tuned/build.sh` now consumes this release directly (via
  `resolve_raft_release()`) instead of CPM-building upstream
  `rapidsai/raft` from source — this release is what that mechanism
  pulls.

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
- `libraft-gb10-cu133.so` — RAFT runtime library, built for SM_121a
- `librmm.so` — RAPIDS Memory Manager (CPM-fetched by raft's own build)
- `librapids_logger.so` — Logging utilities

### Headers (include/)
- `raft/`, `raft_runtime/`, `rmm/`, `rapids_logger/`, `rapids/`, `nvtx3/`

### CMake Configuration (lib/cmake/)
- RAFT CMake targets and configuration files (`raft-config.cmake`,
  `raft-targets.cmake`, etc.) and RMM's own exported config.

## Installation

### Extract the Package
```bash
tar -xjf raft-26.10-gb10-cu133.tar.bz2
cd raft-26.10-gb10-cu133
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
  -DCMAKE_PREFIX_PATH=/path/to/raft-26.10-gb10-cu133 \
  -DCMAKE_CXX_STANDARD=20 \
  -DCMAKE_CUDA_STANDARD=20 \
  -DCMAKE_CUDA_ARCHITECTURES=121a \
  ..
make -j$(nproc)
```

### Install via wheels instead
The `libraft-cu13`/`pylibraft-spark-cu13` wheels for GB10 are published
separately — see
[`v26.08.00-aarch64-cuda133-gb10`](https://github.com/zbrad/raft/releases/tag/v26.08.00-aarch64-cuda133-gb10)
(not yet rebuilt against 26.10.00).

## Compatibility

### API Stability
- **C++ API**: Mostly stable — see "What Changed Upstream" above;
  `raft::runtime::matrix::select_k`'s orphaned declaration was removed
  (#3084), so downstream code referencing it will need updating.
- **CMake Targets**: Stable — `find_package(raft)` + `raft::raft`,
  unaffected by any of the above.
- **Binary Compatibility**: New build; recompile downstream projects
  against this artifact.

### Verify Integrity
```bash
sha256sum -c CHECKSUMS_gb10
```

---

**RAFT Version**: 26.10
**Release Date**: 2026-08-07
**Package**: raft-26.10-gb10-cu133.tar.bz2
**Platform**: aarch64 / SM_121a / CUDA 13.3
