# RAFT 26.10 — GB10 / DGX Spark Release Notes

**Release Date**: 2026-09-08
**Package**: `raft-26.10-gb10-cu133-g37ba10e2.tar.bz2`
**Platform**: aarch64
**GPU Architecture**: SM_121a (GB10 / DGX Spark, Grace Blackwell)
**Commit**: [`37ba10e2`](https://github.com/zbrad/raft/commit/37ba10e2)

## Overview

Rebuild reflecting a real upstream sync (`upstream/main` merge) plus real
fixes and tooling work from this session — supersedes the previous
`v26.10-gb10-cu133` release (2026-08-07, deleted; that tag is now
`v26.10-gb10-cu133-g37ba10e2` — see "Release tag naming" below for why
future releases won't need to delete history to republish).

## What Changed

- **Laplacian NZType fix** — `marked_diagonal` in
  `compute_graph_laplacian` was `device_vector<int>` while
  `thrust::exclusive_scan` expects `device_vector<NZType>`; the mismatch
  caused writes to incorrect memory addresses when `NZType` is 64-bit,
  corrupting the CUDA context on SM_121a with CUDA 13.2+/CCCL 3.4+.
  Regression test: `ComputeGraphLaplacianCOOLongNZType`. Also submitted
  upstream: [NVIDIA/raft#3141](https://github.com/NVIDIA/raft/pull/3141).
- **warpReduce/`raft::add_op` ADL ambiguity — investigated, no raft-side
  fix needed.** The real fix already landed upstream in **cuvs**, not
  raft (`rapidsai/cuvs#1963`, March 2026) — a raft-level PR for this
  (`NVIDIA/raft#3050`) was correctly rejected by a maintainer in July for
  exactly that reason. See `github-com-zbrad-raft/memory/warp_reduce_pr.md`
  for the full history if this ever needs re-deriving.
- **`rapids-cmake` pinned** to a fixed commit
  (`8fc2d05e4b29a2fb7a355192ce19190fcf24c37f`) instead of the previously
  unpinned `main` branch — see `tuned/docs/RELEASE_PINS.md` for why (a
  real `rapids_logger` version mismatch this caused, breaking `zbrad/cuvs`'s
  configure) and the exact commit/URL this and every future release is
  built against.
- **`tuned/regression_test.sh` bug fixed** — was running the laplacian
  fix's check against `LINALG_TEST`, but that test
  (`cpp/tests/sparse/laplacian.cu`) has always built into `SPARSE_TEST`
  per `cpp/tests/CMakeLists.txt`. Both regression checks now correctly
  filtered to their specific test name.
- **Release tag naming**: tags now carry a `-g<short-commit>` suffix
  (this release: `v26.10-gb10-cu133-g37ba10e2`). `VERSION` only bumps on
  a real upstream release cut, so multiple genuinely different rebuilds
  can otherwise collide on the same tag — confirmed directly: had to
  delete-and-recreate the previous `v26.10-gb10-cu133` tag to publish
  this same day's *first* rebuild over the identical Aug 7 release.
- **`tuned/full_test.sh` writes evidence, `tuned/release.sh` requires it**
  — the full C++ gtest suite now writes a timestamped results log
  (`tuned/releases/TEST_RESULTS_gb10.log`) instead of just printing to
  stdout; `release.sh` refuses to publish unless that file exists, is
  newer than the built `.so`, and shows a clean pass. Attached below as a
  release asset.

## Full Test Suite Result

**16/16 gtest binaries passed, 0 failures** — `CORE_TEST`,
`CORE_TEST_NOCUDA`, `EXT_HEADERS_TEST_COMPILED_EXPLICIT`,
`EXT_HEADERS_TEST_COMPILED_IMPLICIT`, `EXT_HEADERS_TEST_IMPLICIT`,
`GEMM_LARGE_TEST`, `LABEL_TEST`, `LINALG_TEST`,
`MATRIX_SELECT_LARGE_TEST`, `MATRIX_SELECT_TEST`, `MATRIX_TEST`,
`RANDOM_TEST`, `SOLVERS_TEST`, `SPARSE_TEST`, `STATS_TEST`, `UTILS_TEST`.
Full output attached as `TEST_RESULTS_gb10.log` on this release.

## Reproducing This Build

```
git clone git@github.com:zbrad/raft.git && cd raft
git checkout 37ba10e2
GPU_TUNED_VARIANT=gb10 bash tuned/build.sh gb10   # pins rapids-cmake internally, see tuned/build.sh
bash tuned/full_test.sh gb10                       # must pass before packaging
bash tuned/package.sh gb10
```

The exact `rapids-cmake` source this build (and `bash tuned/build.sh`
above) resolves against:
```
https://github.com/rapidsai/rapids-cmake/archive/8fc2d05e4b29a2fb7a355192ce19190fcf24c37f.zip
```
See `tuned/docs/RELEASE_PINS.md` for the full table mapping every
published release to its commit + rapids-cmake pin.

## Build Environment

### CUDA Requirements
| Component | Version |
|-----------|---------|
| **CUDA Toolkit** | 13.3 |
| **RMM** | 26.10.00 (CPM-fetched at raft's own C++ configure time) |
| **rapids_logger** | 0.3.0 (via the pinned rapids-cmake commit above) |

### Compiler & Tools
| Component | Version |
|-----------|---------|
| **GCC** | 14.2.0 |
| **CMake** | 4.3.1 |
| **CCCL** | 3.5.0 |

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
tar -xjf raft-26.10-gb10-cu133-g37ba10e2.tar.bz2
cd raft-26.10-gb10-cu133-g37ba10e2
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
  -DCMAKE_PREFIX_PATH=/path/to/raft-26.10-gb10-cu133-g37ba10e2 \
  -DCMAKE_CXX_STANDARD=20 \
  -DCMAKE_CUDA_STANDARD=20 \
  -DCMAKE_CUDA_ARCHITECTURES=121a \
  ..
make -j$(nproc)
```

## Compatibility

### API Stability
- **C++ API**: Stable — only the laplacian NZType internal fix (no
  signature change) since the last release.
- **CMake Targets**: Stable — `find_package(raft)` + `raft::raft`.
- **ABI**: `rapids_logger` moved 0.2.3 → 0.3.0 (transitive, via the
  rapids-cmake pin) — recompile downstream projects against this
  artifact rather than mixing with binaries built against the prior
  release.

### Verify Integrity
```bash
sha256sum -c CHECKSUMS_gb10
```

---

**RAFT Version**: 26.10
**Release Date**: 2026-09-08
**Package**: raft-26.10-gb10-cu133-g37ba10e2.tar.bz2
**Platform**: aarch64 / SM_121a / CUDA 13.3
