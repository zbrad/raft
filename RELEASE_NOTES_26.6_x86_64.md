# RAFT 26.6 Release Notes

**Release Date**: April 1, 2026
**Package**: `raft-26.6-x86_64-cuda132.tar.bz2` (6.4 MB)
**Platform**: x86_64
**GPU Architecture**: SM_120a (Blackwell)

## Overview

RAFT 26.6 is a maintenance release that brings critical bug fixes and CUDA 13.2 support to x86_64 systems. This release includes the `warpReduce` template disambiguation fix required for IVF-PQ workloads and validates the full test suite on x86_64 with CUDA 13.2 / CCCL 3.4.0.

## Fix: warpReduce Template Ambiguity with raft::add_op

### Issue
**Type**: Template Ambiguity / IVF-PQ Build Failure
**Severity**: HIGH
**Affected Component**: `raft/util/reduction.cuh`

When CUB's scan kernels (activated by IVF-PQ) called `warpReduce(val, scan_op)` with `raft::add_op`, both `raft::warpReduce(T, ReduceLambda)` and `cub::detail::scan::warpReduce(Tp, ScanOpT&)` matched, causing an ambiguous template instantiation error with CCCL 3.4.0.

#### Root Cause
CCCL 3.4.0 introduces new warp-level scan primitives that inject `cub::detail::scan::warpReduce` into scope. When `raft::add_op` is passed as the reduction operator, the compiler cannot disambiguate between RAFT's and CUB's overload.

#### Solution
Added an explicit overload in `raft/util/reduction.cuh`:

```cpp
template <typename T>
DI T warpReduce(T val, raft::add_op reduce_op)
{
  return logicalWarpReduce<WarpSize>(val, reduce_op);
}
```

This disambiguates in favour of RAFT's implementation without changing behaviour.

#### Regression Test
`WarpReduceAddOpTest/WarpReduceAddOpTestInt.WARP_REDUCE_WITH_ADD_OP` in `cpp/tests/util/reduction.cu` validates the fix.

## Build Environment

### CUDA Requirements
| Component | Version | Details |
|-----------|---------|---------|
| **CUDA Toolkit** | 13.2.51 | NVIDIA CUDA compiler and libraries |
| **CCCL** | 3.4.0 | NVIDIA CUDA C++ Core Library (Thrust, CUB, libcudacxx) |

### Compiler & Tools
| Component | Version | Details |
|-----------|---------|---------|
| **GCC** | 13.3.0 | C/C++ compiler |
| **CMake** | 3.30.4 | Build system |
| **Python** | 3.x | For Python bindings (optional) |

## Supported Hardware

### Verified
- **NVIDIA Blackwell Architecture**
  - Compute Capability: SM_120a
  - Auto-detected GPU architecture during build

### Compatible
- Other x86_64 systems with NVIDIA GPUs and CUDA 13.2+

## Testing & Validation

### Test Results on x86_64 / CUDA 13.2 / SM_120a

| Test Suite | Tests | Status |
|-----------|-------|--------|
| UTILS_TEST | 183 | ✅ PASSED |
| LINALG_TEST | 2154 | ✅ PASSED |
| **Total** | **2337** | **✅ ALL PASSED** |

### Key Tests Verified
- `WarpReduceAddOpTest/WarpReduceAddOpTestInt.WARP_REDUCE_WITH_ADD_OP` — warpReduce fix confirmed
- Full strided/coalesced reduction suite
- Matrix decompositions (SVD, PCA, TSVD, RSVD)
- Linear algebra primitives (gemm, dot, norm, axpy, etc.)

## Package Contents

### Shared Libraries (lib/)
- `libraft.so` — RAFT runtime library
- `librmm.so` — RAPIDS Memory Manager
- `librapids_logger.so` — Logging utilities

### Headers (include/)
- `raft/` — RAFT algorithm and primitive APIs
- `raft_runtime/` — Runtime headers
- `rmm/` — Memory manager headers
- `rapids_logger/` — Logging framework headers
- `rapids/` — RAPIDS CMake utilities
- `nvtx3/` — NVTX profiling headers

### CMake Configuration (lib/cmake/)
- RAFT CMake targets and configuration files
- RMM dependency configuration
- Rapids Logger configuration

## Installation

### Extract the Package
```bash
tar -xjf raft-26.6-x86_64-cuda132.tar.bz2
cd raft-26.6-x86_64-cuda132
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
  -DCMAKE_PREFIX_PATH=/path/to/raft-26.6-x86_64-cuda132 \
  -DCMAKE_CXX_STANDARD=20 \
  -DCMAKE_CUDA_STANDARD=20 \
  -DCMAKE_CUDA_ARCHITECTURES=120a \
  ..
make -j$(nproc)
```

## What's New vs RAFT 26.04

### Bug Fixes
- ✅ Fixed `warpReduce` template ambiguity with `raft::add_op` (IVF-PQ build failure with CCCL 3.4.0)
- ✅ Corrected regression test expected value for warpReduce reduction

### Build & Environment
- ✅ CUDA 13.2 conda environment files (x86_64 and aarch64)
- ✅ `requirements-build-cuda132.txt` for pip-based Python build setup
- ✅ WSL build scripts for Windows development environments
- ✅ `.gitattributes` enforcing LF line endings for shell scripts

### Validation
- ✅ Full UTILS_TEST (183 tests) and LINALG_TEST (2154 tests) pass on x86_64 + CUDA 13.2

## Compatibility

### API Stability
- **C++ API**: Stable, compatible with RAFT 26.04
- **CMake Targets**: Stable
- **Binary Compatibility**: libraft.so is a new build; recompile downstream projects

### Verify Integrity
```bash
sha256sum -c CHECKSUMS_x86_64
```

---

**RAFT Version**: 26.6
**Release Date**: April 1, 2026
**Package**: raft-26.6-x86_64-cuda132.tar.bz2
**Platform**: x86_64 / SM_120a / CUDA 13.2
