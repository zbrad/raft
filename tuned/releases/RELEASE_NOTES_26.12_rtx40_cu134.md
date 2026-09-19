# RAFT 26.12 — RTX 40 (Ada Lovelace) Release Notes

**Release Date**: 2026-09-19
**Package**: `raft-26.12-rtx40-cu134-ge27a5e00.tar.bz2`
**Platform**: x86_64 (built and tested on WSL2, Ubuntu 24.04)
**GPU Architecture**: SM_89 (Ada Lovelace, RTX 40 series)
**Commit**: [`e27a5e00`](https://github.com/zbrad/raft/commit/e27a5e00)

## Overview

First RTX 40 release of the tuned RAFT build. Same source as the GB10
26.12 release (upstream `NVIDIA/raft` `main` merged into `tuned-builds`),
built single-arch for `sm_89` against CUDA 13.4.

## What Changed

- **New variant.** `tuned/devices/rtx40.conf` targets bare `sm_89`; Ada has no
  family-specific ("a") ISA variant, so nothing beyond the generic target
  applies.
- **`Raft.InterruptibleOpenMP` is skipped under WSL2 only.** The test assumes
  10 host threads' GPU kernels overlap in real time in launch order. On
  WSL2 that does not hold: it failed about 70% of runs with a varying
  finished-thread count (3 to 10), and still failed 37 of 50 runs with a
  five-times-wider timing step, so it is not a timing-margin problem. It passes
  on native Linux (GB10). `tuned/raft_test_common.sh` skips it only when
  `/proc/version` reports WSL, so native runs still exercise it. A proper fix is
  an upstream rewrite of the test (explicit synchronization instead of sleep
  durations).
- **Build-environment trap on Ubuntu WSL, no source change.** Ubuntu's own
  CUDA 12.0 dev packages (`nvidia-cuda-toolkit`, `nvidia-cuda-dev`) must be
  removed before configuring: `nvidia-cuda-dev` leaves a second
  `libcudart_static.a` in `/usr/lib` that breaks linking, and if present at
  configure time CMake caches the CUDA 12 `libcublas` and friends. After
  any toolkit change, `grep -c /usr/lib/x86_64-linux-gnu/libcu
  cpp/build-rtx40/CMakeCache.txt` should print 0.

## Full Test Suite Result

**16/16 gtest binaries passed, 0 failures**, with the one WSL skip above in
`CORE_TEST` — `CORE_TEST`, `CORE_TEST_NOCUDA`,
`EXT_HEADERS_TEST_COMPILED_EXPLICIT`, `EXT_HEADERS_TEST_COMPILED_IMPLICIT`,
`EXT_HEADERS_TEST_IMPLICIT`, `GEMM_LARGE_TEST`, `LABEL_TEST`, `LINALG_TEST`,
`MATRIX_SELECT_LARGE_TEST`, `MATRIX_SELECT_TEST`, `MATRIX_TEST`,
`RANDOM_TEST`, `SOLVERS_TEST`, `SPARSE_TEST`, `STATS_TEST`, `UTILS_TEST`.
Full output attached as `TEST_RESULTS_rtx40.log` on this release. Run on
WSL2 with `memory=48GB` (`MATRIX_SELECT_TEST` peaks near 29 GB).

## Reproducing This Build

```
git clone git@github.com:zbrad/raft.git && cd raft
git checkout e27a5e00
bash tuned/build.sh rtx40            # pins rapids-cmake internally, see tuned/build.sh
bash tuned/full_test.sh rtx40        # must pass before packaging
bash tuned/package.sh rtx40
```

The exact `rapids-cmake` source this build resolves against:
```
https://github.com/rapidsai/rapids-cmake/archive/8fc2d05e4b29a2fb7a355192ce19190fcf24c37f.zip
```

## Build Environment

| Component | Version |
|-----------|---------|
| **CUDA Toolkit** | 13.4 (13.4.92) |
| **CCCL** | 3.5.0 |
| **Host compiler** | GCC 13.3.0 (Ubuntu 24.04) |
| **CMake** | 4.4.3 |
| **OS** | Ubuntu 24.04 on WSL2, x86_64 |

## Supported Hardware

### Verified
- **NVIDIA GeForce RTX 4090** (Ada Lovelace, SM_89), driver passthrough from
  Windows to WSL2; no Linux driver installed in WSL.

### Expected, not tested
- Other RTX 40 series GPUs: the binary is single-arch `sm_89`, which covers the
  whole 40 series, but only the RTX 4090 was run.
- Native x86_64 Linux: not run. Only WSL2 has been tested.

## Package Contents

- `lib/libraft-rtx40-cu134.so` — RAFT runtime library, built for SM_89
- `include/`, `lib/cmake/` — headers and CMake config for `find_package(raft)`,
  plus the RMM and rapids_logger dependencies raft's own build fetched

## Installation

```bash
tar -xjf raft-26.12-rtx40-cu134-ge27a5e00.tar.bz2
cd raft-26.12-rtx40-cu134-ge27a5e00
export CMAKE_PREFIX_PATH="$(pwd):${CMAKE_PREFIX_PATH}"
export LD_LIBRARY_PATH="$(pwd)/lib:${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}"
```

```cmake
find_package(raft REQUIRED)
target_link_libraries(my_target PRIVATE raft::raft)
```

Configure your project with `-DCMAKE_CUDA_ARCHITECTURES=89`.

### Verify Integrity
```bash
sha256sum -c CHECKSUMS_rtx40
```

---

**RAFT Version**: 26.12.00
**Release Date**: 2026-09-19
**Package**: raft-26.12-rtx40-cu134-ge27a5e00.tar.bz2
**Platform**: x86_64 / SM_89 / CUDA 13.4
