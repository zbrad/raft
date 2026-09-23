# RAFT 26.12 — GB10 / DGX Spark Release Notes

**Release Date**: 2026-09-22
**Package**: `raft-26.12-gb10-cu134-ga57c8910.tar.bz2`
**Platform**: aarch64
**GPU Architecture**: SM_121a (GB10 / DGX Spark, Grace Blackwell)
**Commit**: [`a57c8910`](https://github.com/zbrad/raft/commit/a57c8910)

## Overview

Supersedes `v26.12-gb10-cu134-g9d97792e` (2026-09-18). No library source
changed between that release and this one (`git diff --stat
9d97792e..a57c8910 -- cpp/` is empty) — this rebuild exists to publish
under the CUDA-version-distinct output-directory layout (below), and to
carry the `zbrad/cuvs` pairing note now that a cu133 raft/cuvs pair has
been published (see "Compatible cuVS" below). Everything in the original
`v26.12-gb10-cu134-g9d97792e` release notes' "What Changed" section
(CUDA 13.4 toolkit, the `cuda::stream_ref` migration and its fallout,
the fork-local `ComputeGraphLaplacianCOOLongNZType` fix) still applies
unchanged to this build; not repeated here.

**Build outputs are now CUDA-version-distinct.** `tuned/build.sh`,
`package.sh` and `full_test.sh` write to `cpp/build/<cuda_tag>/<variant>`,
`dist/<cuda_tag>/<variant>` and `tuned/releases/<cuda_tag>/` respectively,
so a cu133 and cu134 build (or test-results gate) can no longer collide
or silently satisfy each other's freshness check.

## What Changed

- **CUDA 13.4 toolkit.** `gpu_tuned_resolve_cuda_home` auto-selects the
  highest installed `/usr/local/cuda-<ver>` toolkit; no script changes
  needed.
- **Upstream sync (26.10 → 26.12.00)** — brought in, among other things,
  [`NVIDIA/raft#3129`](https://github.com/NVIDIA/raft/pull/3129) "Migrate
  stream APIs from `rmm::cuda_stream_view` to `cuda::stream_ref`" and its
  follow-up [`#3136`](https://github.com/NVIDIA/raft/pull/3136). Required:
  the CCCL version this build pulls in (3.5.0, unconditionally pinned via
  `rapids-cmake`'s `8fc2d05e...` SHA — not new to this release, just never
  previously exercised by a from-scratch build) dropped implicit
  `cuda::stream_ref` → `cudaStream_t` conversion, which broke
  `wait_stream_pool_on_stream` in `cuda_stream_pool.hpp`. This is not
  CUDA-13.4-specific — independently hit on an rtx40 build too.
- **Fork-local regression test fix** — `ComputeGraphLaplacianCOOLongNZType`
  (added in the 26.10 release above; not present upstream) called
  `raft::sparse::op::coo_sort(..., raft::resource::get_cuda_stream(res))`
  without `.get()`, same migration debt as above but our own to pay since
  upstream doesn't have this test. Fixed in `9d97792e`.
- **`tuned/build.sh` gap found, not yet fixed**: its `bash build.sh
  libraft tests --compile-lib ...` call does not fail the script when a
  test target fails to compile — `verify_arch`, `verify_cccl`, and
  `embed_build_info` all run and the script exits 0 regardless.
  `tuned/package.sh`'s fresh-passing-`full_test.sh` gate is the only
  thing that actually catches a broken test suite.

## Full Test Suite Result

**16/16 gtest binaries passed, 0 failures** — `CORE_TEST`,
`CORE_TEST_NOCUDA`, `EXT_HEADERS_TEST_COMPILED_EXPLICIT`,
`EXT_HEADERS_TEST_COMPILED_IMPLICIT`, `EXT_HEADERS_TEST_IMPLICIT`,
`GEMM_LARGE_TEST`, `LABEL_TEST`, `LINALG_TEST`,
`MATRIX_SELECT_LARGE_TEST`, `MATRIX_SELECT_TEST`, `MATRIX_TEST`,
`RANDOM_TEST`, `SOLVERS_TEST`, `SPARSE_TEST`, `STATS_TEST`, `UTILS_TEST`.
237 individual tests passed. Re-run 2026-09-22 against this build (same
counts as the original `9d97792e` run, as expected since no library
source changed). Full output attached as `TEST_RESULTS_gb10.log` on this
release.

## Compatible cuVS

This RAFT release is 26.12, so it pairs with cuVS 26.12 (`tuned-builds`,
which tracks upstream `main`). See the CUDA 13.3 release notes
(`RELEASE_NOTES_26.12_gb10_cu133.md`, "Compatible cuVS" section) for the
full RAFT/cuVS version-pairing background — unchanged here, just repeated
per CUDA toolkit below.

| This RAFT release | cuVS release built and tested against it |
|---|---|
| `v26.12-gb10-cu134-ga57c8910` | _pending: the matching cuVS cu134 release has not been rebuilt against this RAFT release yet (the published `v26.12-gb10-cu134-g6bb1419c` was built against the superseded `9d97792e`)_ |

Use a cuVS build from the same 26.12 line with this RAFT. A cuVS built from a
different RAPIDS version, or against a different CUDA toolkit than the one this
RAFT was built with, is not covered by these tests.

## Reproducing This Build

```
git clone git@github.com:zbrad/raft.git && cd raft
git checkout a57c8910
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
| **CUDA Toolkit** | 13.4 |
| **RMM** | 26.12.0 (CPM-fetched at raft's own C++ configure time) |
| **rapids_logger** | 0.3.0 (via the pinned rapids-cmake commit above) |

### Compiler & Tools
| Component | Version |
|-----------|---------|
| **GCC** | 14.2.0 |
| **CMake** | 4.4.3 |
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
- `libraft-gb10-cu134.so` — RAFT runtime library, built for SM_121a
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
tar -xjf raft-26.12-gb10-cu134-ga57c8910.tar.bz2
cd raft-26.12-gb10-cu134-ga57c8910
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
  -DCMAKE_PREFIX_PATH=/path/to/raft-26.12-gb10-cu134-ga57c8910 \
  -DCMAKE_CXX_STANDARD=20 \
  -DCMAKE_CUDA_STANDARD=20 \
  -DCMAKE_CUDA_ARCHITECTURES=121a \
  ..
make -j$(nproc)
```

## Compatibility

### API Stability
- **C++ API**: Stable, modulo the upstream `cuda::stream_ref` migration
  (see "What Changed" above) — a build-time-visible change (raw
  `cudaStream_t` call sites need `.get()`), not a public-API signature
  change for normal `find_package(raft)` consumers.
- **CMake Targets**: Stable — `find_package(raft)` + `raft::raft`.
- **ABI**: RMM moved 26.10.00 → 26.12.0 (transitive, via the upstream
  version bump) — recompile downstream projects against this artifact
  rather than mixing with binaries built against the prior release.

### Verify Integrity
```bash
sha256sum -c CHECKSUMS_gb10
```

---

**RAFT Version**: 26.12.00
**Release Date**: 2026-09-22
**Package**: raft-26.12-gb10-cu134-ga57c8910.tar.bz2
**Platform**: aarch64 / SM_121a / CUDA 13.4
