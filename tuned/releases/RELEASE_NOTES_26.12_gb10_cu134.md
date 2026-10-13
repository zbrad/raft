# RAFT 26.12 — GB10 / DGX Spark Release Notes

**Release Date**: 2026-10-12
**Package**: `raft-26.12-gb10-cu134-g<commit>.tar.bz2` (`<commit>` is the 8-hex suffix of this release's tag)
**Platform**: aarch64
**GPU Architecture**: SM_121a (GB10 / DGX Spark, Grace Blackwell)
**Commit**: the tag's `-g<commit>` suffix; `git log --oneline` from it shows exactly what is in this release

## Overview

Supersedes `v26.12-gb10-cu134-g3a508503` (published earlier the same day, rapids-cmake `8fc2d05e`),
which itself superseded `v26.12-gb10-cu134-ga57c8910` (2026-09-22). This build brings `tuned-builds`
up to upstream `rapidsai/raft` `main` at `56b4b2ef` by merging 9 upstream commits it did not have:
`#3161` build type override via env var, `#3118` sparse MST solver performance, `#3133` no
unintended FP64 promotion in float kernels, `#3170` per-cluster std indexing fix in `make_blobs`,
`#3163` removal of the remaining `rmm/cuda_stream_view.hpp` includes, `#3164`, `#3167` and `#3162`
(CI, docs and wheel size housekeeping), and the changelog. It also finishes the fork-local test fix
described below, moves the shared rapids-cmake pin (below), and publishes the first build made in
the new per-toolkit build layout. No release tag shape change: consumers that look up
`v<ver>-<variant>-<cuda>-g<sha>` (zbrad/cuvs, zbrad/faiss) are unaffected.

**Build outputs now live in one tree per toolkit, `tuned/build/<cuda_tag>/`** (no variant level):
`cmake/` (the one fixed compile path), `dist/`, `dist-shared/`, `releases/` (generated checksums
and test logs), `ccache/`, `timing.tsv`. Before, they were `cpp/build/<cuda_tag>/<variant>`,
`dist/<cuda_tag>/<variant>` and `tuned/releases/<cuda_tag>/`. The fixed compile path is what lets
ccache hit across rebuilds: measured on this build, cold 275 s of ninja wall time (262 targets,
4,140 s summed) against 1 s warm with 240/240 ccache hits (20 s for the whole `build.sh`).

## What Changed

- **Unique shared-object identities for the rapids chain.** `librmm.so` and `librapids_logger.so`
  carried the same file names and SONAMEs as stock RAPIDS, so a stock install (or an
  `LD_LIBRARY_PATH` pointing at one) could be loaded in place of ours, or ours in place of theirs.
  They are now **`librmm-tuned.so`** and **`librapids_logger-tuned.so`**: file name, SONAME and every
  `DT_NEEDED` that names them, and the installed CMake import files (`rmm-targets-release.cmake`,
  `rapids_logger-targets-release.cmake`) point at the new names, so `find_package(raft)` consumers
  link them without changes. `libraft-gb10-cu134.so` already carries variant and CUDA tag and keeps
  its name; `libraft.a` is an archive with no SONAME. The rename is a patchelf pass at packaging time
  (`tuned/package.sh`, `gpu_tuned_rename_sonames`), and packaging fails closed unless every shared
  object is renamed or kept and every dependency resolves inside the tree. **This is a breaking
  change for anything that loaded `librmm.so` / `librapids_logger.so` from an earlier raft
  release by name**; rebuild such consumers against this release (zbrad/cuvs and zbrad/faiss do).
  The library code is identical to `v26.12-gb10-cu134-ga5db5823`; only the shipped names differ.
- **nvtx3 is now fetched and shipped.** The previous raft packages did not contain nvtx3, although
  the installed `rmm-dependencies.cmake` calls `find_dependency(nvtx3)`: the build had resolved
  nvtx3 from a stock pip `librmm` wheel in the build host's user site-packages, so CMake never
  fetched it and never installed it. A consumer configured against the package alone (zbrad/faiss)
  failed with nvtx3 missing. The build now ignores user-site pip CMake packages
  (`CMAKE_IGNORE_PREFIX_PATH`), so nvtx3 is fetched at the pinned rapids-cmake and installed
  (`lib/cmake/nvtx3/`, `include/nvtx3/`; 3.2.0, header-only, so it has no `-tuned` shared object).
  The build fails if any `*_DIR` in its CMake cache points into a pip wheel, and packaging fails
  unless nvtx3 is in the package and a minimal consumer project configures against the package
  alone with `nvtx3`, `rmm` and `rapids_logger` resolving inside it. A stock wheel's nvtx3 is not
  the tuned, tested copy, and the build warns loudly when such a wheel is installed.
- **Shared rapids-cmake pin moved `8fc2d05e` -> `61a96c8f`.** rapids-cmake's "Update cuco for
  RoaringBitmap use in cuVS (#1095)". The merged zbrad/cuvs (upstream `#2446`, roaring-bitmap CAGRA
  filter) calls `cuco::roaring_bitmap::from_indices`, which the older pinned cuco lacks, so cuvs could
  not compile against the old pin. Exactly two packages differ between the pins, read from each
  commit's `rapids-cmake/cpm/versions.json`: **cuco** `4b26118c` -> `8ed532dc` (raft does not use or
  export cuco), and **CCCL**, labelled 3.5.0 in both, commit `399863ef` -> `b98d4bd6` (the 3.5.0-rc1
  update, which raft does build against). This build's configure log shows it fetched the new
  rapids-cmake and found CCCL 3.5.0; the library is rebuilt and the whole suite rerun under the new
  pin, same counts as before. Changed in zbrad/cuvs in the same sitting (sibling pin).

- **Upstream sync to `main` `56b4b2ef`** (the 9 commits listed above). Gate output: all
  fork markers held (137 `gpu_tuned_` lines before and after); the one file the tool flagged,
  `dependencies.yaml`, lost 24 lines only because upstream itself removed six nightly
  `extra-index-url` blocks that our commits never touched.
- **Fork-local regression test fixed, again.** `run_warp_reduce_with_add_op` (our
  `7fcef655`, the warpReduce/`raft::add_op` ambiguity test) still took `rmm::cuda_stream_view`
  and launched with `<<<>>>`; upstream's `#3129` had moved the rest of that file to
  `cuda::stream_ref`, `raft::launch_kernel` and `stream.sync()`, and this merge's `#3163` removed the
  last include that still declared `rmm::cuda_stream_view` there, so `UTILS_TEST` failed to compile.
  Fixed in `67b37c2b`.
- **`tuned/build.sh` now fails when a target did not build.** The gap recorded in the previous
  notes ("does not fail the script when a test target fails to compile") is closed in `80490e0c`:
  a ninja dry run after the build must show no pending compile and no pending link whose
  executable is missing. It mattered here: the first test run on this merge reported
  "15/15 passed" while `UTILS_TEST` was silently absent, and was discarded.
- **`tuned/package.sh` writes the tarball to `tuned/build/<cuda_tag>/dist/`**, not the repo root,
  and `tuned/build.sh` runs an explicit `cmake --install` (the install tree it packages).

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

**16/16 gtest binaries passed, 0 failed; 7,605 tests passed, 44 skipped.** Binaries:
`CORE_TEST`, `CORE_TEST_NOCUDA`, `EXT_HEADERS_TEST_COMPILED_EXPLICIT`,
`EXT_HEADERS_TEST_COMPILED_IMPLICIT`, `EXT_HEADERS_TEST_IMPLICIT`, `GEMM_LARGE_TEST`,
`LABEL_TEST`, `LINALG_TEST`, `MATRIX_SELECT_LARGE_TEST`, `MATRIX_SELECT_TEST`, `MATRIX_TEST`,
`RANDOM_TEST`, `SOLVERS_TEST`, `SPARSE_TEST`, `STATS_TEST`, `UTILS_TEST` (237 tests, including the
fork-local `WarpReduceAddOpTest`). Skipped: 4 in `CORE_TEST` that require at least 2 CUDA devices
(this host has one GPU), and 40 `SelectK` parameter cases in `MATRIX_SELECT_TEST` that the test
itself skips (`select_k.cuh:232`, no reason printed). Run 2026-10-13 against the build at commit
`adfe914d` (the first build that fetches and ships nvtx3; the library code is unchanged from the
`798e2ea8` build), started 20:10Z and finished 20:32Z, one binary at a time; the same counts came
out of the earlier runs. Full output attached as `TEST_RESULTS_gb10.log` on this release.

## Compatible cuVS

This RAFT release is 26.12, so it pairs with cuVS 26.12 (`tuned-builds`,
which tracks upstream `main`). See the CUDA 13.3 release notes
(`RELEASE_NOTES_26.12_gb10_cu133.md`, "Compatible cuVS" section) for the
full RAFT/cuVS version-pairing background — unchanged here, just repeated
per CUDA toolkit below.

| This RAFT release | cuVS release built and tested against it |
|---|---|
| this release | _pending: the matching cuVS cu134 release has not been rebuilt against this RAFT release yet (the published `v26.12-gb10-cu134-g6bb1419c` was built against the superseded `9d97792e`)_ |

Use a cuVS build from the same 26.12 line with this RAFT. A cuVS built from a
different RAPIDS version, or against a different CUDA toolkit than the one this
RAFT was built with, is not covered by these tests.

## Reproducing This Build

```
git clone git@github.com:zbrad/raft.git && cd raft
git checkout <the release tag>
GPU_TUNED_VARIANT=gb10 bash tuned/build.sh gb10   # pins rapids-cmake internally, see tuned/build.sh
bash tuned/full_test.sh gb10                       # must pass before packaging
bash tuned/package.sh gb10
```

The exact `rapids-cmake` source this build (and `bash tuned/build.sh`
above) resolves against:
```
https://github.com/rapidsai/rapids-cmake/archive/61a96c8f29731affd7fd913a586673dd057dc3b0.zip
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
- `librmm-tuned.so` — RAPIDS Memory Manager (CPM-fetched by raft's own build)
- `librapids_logger-tuned.so` — Logging utilities

### Headers (include/)
- `raft/`, `raft_runtime/`, `rmm/`, `rapids_logger/`, `rapids/`, `nvtx3/`

### CMake Configuration (lib/cmake/)
- RAFT CMake targets and configuration files (`raft-config.cmake`,
  `raft-targets.cmake`, etc.) and RMM's own exported config.

## Installation

### Extract the Package
```bash
tar -xjf raft-26.12-gb10-cu134-g<commit>.tar.bz2
cd raft-26.12-gb10-cu134-g<commit>
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
  -DCMAKE_PREFIX_PATH=/path/to/raft-26.12-gb10-cu134-g<commit> \
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
**Release Date**: 2026-10-12
**Package**: raft-26.12-gb10-cu134-g<commit>.tar.bz2
**Platform**: aarch64 / SM_121a / CUDA 13.4
