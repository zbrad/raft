# RAFT 26.6 Release - aarch64 + CUDA 13.2

**Release Date**: April 6, 2026

## 📦 Release Packages

| File | Size | Description |
|------|------|-------------|
| `raft-26.6-aarch64-cuda132.tar.bz2` | 3.2 MB | C++ headers, shared libraries, CMake targets |
| `libraft_cu13-26.6.0-py3-none-linux_aarch64.whl` | 3.3 MB | C++ runtime wheel — bundles `libraft.so` (SM_121) |
| `pylibraft_spark_cu13-26.6.0-cp311-abi3-linux_aarch64.whl` | 336 KB | Python wheel — Cython extensions (SM_121 only) |

**Platform**: aarch64 (ARM-based, NVIDIA GB10 / DGX Spark)  
**CUDA**: 13.2+  
**Architecture**: SM_121 (GB10)

## 🚨 Critical Fix

This release addresses a **CRITICAL BUG** in the sparse Laplacian computation that caused CUDA context corruption on aarch64 systems with CCCL 3.4.0.

### The Fix
Type mismatch in `raft/sparse/linalg/detail/laplacian.cuh`:
- Changed `int` to `NZType` for 64-bit index support
- Eliminates memory corruption in thrust::exclusive_scan
- Full test coverage verified (483 tests pass)

**See**: `RELEASE_NOTES_26.6.md` for complete details

## 📋 Files in This Release

| File | Purpose |
|------|---------|
| `raft-26.6-aarch64-cuda132.tar.bz2` | C++ libraries, headers, CMake configs |
| `libraft_cu13-26.6.0-py3-none-linux_aarch64.whl` | C++ runtime wheel (bundles `libraft.so`) |
| `pylibraft_spark_cu13-26.6.0-cp311-abi3-linux_aarch64.whl` | Python wheel (SM_121-only Cython extensions) |
| `CHECKSUMS` | SHA256 and MD5 checksums for package verification |
| `RELEASE_NOTES_26.6_aarch64.md` | Complete release notes with fix details and technical info |
| `INSTALL_GUIDE_26.6_aarch64.md` | Quick start installation and usage guide |
| `RELEASE_README_26.6_aarch64.md` | This file |

## 🚀 Quick Start

**C++ (tar package):**
```bash
# 1. Extract
tar -xjf raft-26.6-aarch64-cuda132.tar.bz2

# 2. Set environment
export RAFT_ROOT=$(pwd)/raft-26.6-aarch64-cuda132
export LD_LIBRARY_PATH=$RAFT_ROOT/lib:${LD_LIBRARY_PATH}
export CMAKE_PREFIX_PATH=$RAFT_ROOT:${CMAKE_PREFIX_PATH}

# 3. Use in your project
cmake -DCMAKE_PREFIX_PATH=$RAFT_ROOT ..
```

**Python (pip — DGX Spark / SM_121 only):**
```bash
BASE=https://github.com/zbrad/raft/releases/download/v26.06.00-aarch64-cuda132-spark
pip install \
    --extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple \
    "${BASE}/libraft_cu13-26.6.0-py3-none-linux_aarch64.whl" \
    "${BASE}/pylibraft_spark_cu13-26.6.0-cp311-abi3-linux_aarch64.whl"
```

For detailed instructions, see `INSTALL_GUIDE_26.6_aarch64.md`

## 📊 Hardware Support

### ✅ Primary Support
- **NVIDIA Grace Hopper** (DGX Spark)
  - Compute Capability: SM_121a
  - Architecture: aarch64
  - Memory: Up to 288GB GPU memory

### ✅ Secondary Support  
- Other aarch64 systems with NVIDIA GPUs
- CUDA 13.2+ with CCCL 3.4.0+

### 💡 Note
This is an aarch64-specific release. x86-64 users should continue with RAFT 26.04 until RAFT 27.0.

## 🔍 Package Contents

### Libraries (lib/)
```
libraft.so               - RAFT runtime library
librmm.so              - RAPIDS Memory Manager
librapids_logger.so    - Logging utilities
cmake/                 - CMake configuration files (30+ files)
```

### Headers (include/)
```
raft/                  - RAFT algorithms & primitives (2,778+ files)
rapids_logger/         - Logger headers
rmm/                   - Memory manager headers
```

**Total**: 2,832 files, 3.2 MB

## ✅ Testing & Validation

- **Tests Run**: 483
- **Suites**: 65
- **Status**: ✅ ALL PASSED
- **Runtime**: ~514 seconds on Grace Hopper

**Key Tests**:
- ✅ ComputeGraphLaplacianTest (GraphWithoutSelfLoop, GraphWithSelfLoop)
- ✅ ComputeGraphLaplacianNormalizedCSR
- ✅ All sparse linear algebra operations
- ✅ Distance metrics, clustering, decomposition

## 🔐 Verification

**Verify package integrity:**

```bash
# Check SHA256 (recommended)
sha256sum -c CHECKSUMS

# Check MD5
md5sum -c CHECKSUMS
```

Expected checksums from `CHECKSUMS` file:
```
SHA256: 29730aeaf10df726e914632409af9c48137c7f5bb2648165945fe7b16afb4c87
MD5:    194e4f4b29af97b897d44cda2de7b145
```

## 📖 Documentation

### For Installation
→ See **`INSTALL_GUIDE_26.6.md`**
- Step-by-step setup
- Environment configuration
- CMake integration examples
- Troubleshooting guide

### For Technical Details
→ See **`RELEASE_NOTES_26.6.md`**
- Complete fix explanation
- CUDA/compiler requirements
- Performance considerations
- Compatibility information

### For RAFT Overview
→ See original repository:
- [RAFT GitHub](https://github.com/rapidsai/raft)
- [RAFT Documentation](https://docs.rapids.ai/api/raft)

## 🔧 System Requirements

| Component | Requirement |
|-----------|-------------|
| **CPU Architecture** | aarch64 (ARM-based) |
| **GPU Architecture** | SM_121a (Grace Hopper) recommended |
| **CUDA Toolkit** | 13.2+ |
| **CCCL** | 3.4.0+ |
| **GCC/Clang** | 13.3.0+ |
| **CMake** | 3.26.4+ |

## 🆚 What's New in 26.6

### Critical Fixes ⚠️
- ✅ Fixed Laplacian computation type mismatch
- ✅ Eliminated CUDA context corruption on aarch64
- ✅ Full 64-bit index support in sparse algorithms

### Verified On
- ✅ NVIDIA DGX Spark with Grace Hopper GPUs
- ✅ CUDA 13.2.51
- ✅ CCCL 3.4.0
- ✅ GCC 13.3.0

### Testing
- ✅ 483 tests pass
- ✅ Sparse matrix operations validated
- ✅ Graph algorithms verified
- ✅ Linear algebra routines confirmed

## 🤝 Support & Feedback

### Report Issues
https://github.com/zbrad/raft/issues

### Questions?
1. Check `INSTALL_GUIDE_26.6_aarch64.md` for common issues
2. Review `RELEASE_NOTES_26.6_aarch64.md` for technical details
3. Open an issue on GitHub with:
   - CUDA version (`nvcc --version`)
   - GPU architecture (`nvidia-smi`)
   - Build output
   - Error messages

## 📝 License

RAFT is licensed under the Apache License 2.0. See the RAFT repository for details.

---

## 🎯 Next Steps

1. **Verify your system**: Check prerequisites in INSTALL_GUIDE_26.6.md
2. **Extract the package**: `tar -xjf raft-26.6-aarch64-cuda132.tar.bz2`
3. **Set environment**: Export CMAKE_PREFIX_PATH and LD_LIBRARY_PATH
4. **Test integration**: Try the example in INSTALL_GUIDE_26.6.md
5. **Build your project**: Use CMake or manual compilation methods

## 📦 Release Artifacts

```
raft-26.6-aarch64-cuda132/
├── lib/
│   ├── libraft.so
│   ├── librmm.so
│   ├── librapids_logger.so
│   └── cmake/
│       ├── raft/
│       ├── rmm/
│       └── rapids_logger/
└── include/
    ├── raft/          (2,778+ headers)
    ├── rapids_logger/
    └── rmm/
```

**Total Size**: 3.2 MB  
**Files**: 2,832  
**Checksum**: See CHECKSUMS

---

**RAFT Release 26.6**  
April 6, 2026  
Platform: aarch64 (NVIDIA GB10 / DGX Spark)  
