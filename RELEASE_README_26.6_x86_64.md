# RAFT 26.6 — x86_64 Release

**Date**: April 1, 2026 | **CUDA**: 13.2 | **Arch**: x86_64 / SM_120a (Blackwell)

## What's New

- **Fix**: `warpReduce` template ambiguity with `raft::add_op` — required for IVF-PQ with CCCL 3.4.0
- **Validated**: 2337 tests pass on x86_64 + CUDA 13.2 + SM_120a
- **Build**: WSL build scripts and LF line-ending enforcement added

## Quick Start

```bash
# Verify and extract
sha256sum -c CHECKSUMS_x86_64
tar -xjf raft-26.6-x86_64-cuda132.tar.bz2

# Set environment
export RAFT_ROOT="$(pwd)/raft-26.6-x86_64-cuda132"
export LD_LIBRARY_PATH="${RAFT_ROOT}/lib:${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}"
export CMAKE_PREFIX_PATH="${RAFT_ROOT}:${CMAKE_PREFIX_PATH}"
```

## CMake Integration

```cmake
find_package(raft REQUIRED)
target_link_libraries(my_target PRIVATE raft::raft)
```

```bash
cmake -DCMAKE_PREFIX_PATH=${RAFT_ROOT} \
      -DCMAKE_CUDA_ARCHITECTURES=120a \
      ..
```

## Package Contents

| Path | Contents |
|------|---------|
| `lib/` | libraft.so, librmm.so, librapids_logger.so + CMake configs |
| `include/raft/` | RAFT algorithm and primitive headers |
| `include/rmm/` | RAPIDS Memory Manager headers |
| `include/raft_runtime/` | Runtime headers |

## Test Results

| Suite | Tests | Result |
|-------|-------|--------|
| UTILS_TEST | 183 | ✅ PASSED |
| LINALG_TEST | 2154 | ✅ PASSED |

## Requirements

- x86_64 Linux
- CUDA 13.2+
- NVIDIA GPU (SM_120a verified; other Ampere/Hopper/Blackwell compatible)
- CMake 3.30.4+
- GCC 13+

## Documentation

| File | Purpose |
|------|---------|
| `RELEASE_NOTES_26.6_x86_64.md` | Technical details, fix description, test results |
| `CHECKSUMS_x86_64` | SHA256 + MD5 for package verification |

---

**RAFT 26.6** | x86_64 | CUDA 13.2 | April 1, 2026
