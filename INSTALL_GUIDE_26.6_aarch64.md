# RAFT 26.6 Quick Installation Guide

**For aarch64 systems with NVIDIA Grace Hopper GPUs and CUDA 13.2**

## Prerequisites

Verify your system meets these requirements:

```bash
# Check CUDA version (must be 13.2+)
nvcc --version

# Check GPU architecture (should show SM 121a for Grace Hopper)
nvidia-smi --query-gpu=compute_cap --format=csv

# Check CPU architecture (must be aarch64)
uname -m
```

Expected output:
```
CUDA 13.2.51
compute_cap: 12.1
aarch64
```

## Installation Steps

### 1. Extract the Package

```bash
tar -xjf raft-26.6-aarch64-cuda132.tar.bz2
export RAFT_ROOT=$(pwd)/raft-26.6-aarch64-cuda132
```

### 2. Verify Package Contents

```bash
ls -la $RAFT_ROOT/
# Output should show: lib/ include/

ls $RAFT_ROOT/lib/
# Output: libraft.so, librmm.so, librapids_logger.so, cmake/

ls $RAFT_ROOT/include/ | head
# Output: raft/, rapids_logger/, rmm/
```

### 3. Set Environment Variables

```bash
# Add to your shell profile (~/.bashrc, ~/.zshrc, etc.) or source temporarily:
export RAFT_CMAKE_PREFIX="$RAFT_ROOT"
export LD_LIBRARY_PATH="$RAFT_ROOT/lib:${CUDA_HOME:-/usr/local/cuda}/lib64:${LD_LIBRARY_PATH}"
export CMAKE_PREFIX_PATH="$RAFT_ROOT:${CMAKE_PREFIX_PATH}"
```

### 4. Verify Installation

```bash
# Check that RAFT cmake config is present
ls $RAFT_ROOT/lib/cmake/raft/

# Confirm libraft.so exists and links correctly
ldd $RAFT_ROOT/lib/libraft.so | grep -E 'cuda|rmm|not found'
```

## Using RAFT in Your Project

### Option A: CMake Project

**CMakeLists.txt:**
```cmake
cmake_minimum_required(VERSION 3.30.4 LANGUAGES CXX CUDA)
project(MyRaftProject LANGUAGES CXX CUDA)

# Set RAFT location
set(CMAKE_PREFIX_PATH "$ENV{RAFT_CMAKE_PREFIX}" CACHE PATH "RAFT prefix")

# Find and link RAFT
find_package(raft REQUIRED)

# Create your target
add_executable(my_program main.cu)

# Link against RAFT
target_link_libraries(my_program PRIVATE raft::raft)

# Set CUDA standards
set_target_properties(my_program PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CUDA_STANDARD 20
  CUDA_STANDARD_REQUIRED ON
)
```

**Build your project:**
```bash
cd my_project
mkdir build && cd build
cmake -DCMAKE_PREFIX_PATH=$RAFT_ROOT ..
make -j$(nproc)
```

### Option B: Manual Compilation

```bash
# Compile with explicit paths
nvcc -std=c++20 \
  -I$RAFT_ROOT/include \
  -L$RAFT_ROOT/lib \
  -lraft -lrmm -lrapids_logger \
  -o my_program main.cu

# Run with proper library paths
export LD_LIBRARY_PATH=$RAFT_ROOT/lib:$LD_LIBRARY_PATH
./my_program
```

## Troubleshooting

### Issue: `libraft.so: cannot open shared object file`

**Solution:**
```bash
export LD_LIBRARY_PATH=$RAFT_ROOT/lib:${LD_LIBRARY_PATH}
```

### Issue: CMake cannot find RAFT

**Solution:**
```bash
# Explicitly set the prefix path
cmake -DCMAKE_PREFIX_PATH=$RAFT_ROOT ..

# Or add to CMakeLists.txt:
list(PREPEND CMAKE_PREFIX_PATH "$ENV{RAFT_CMAKE_PREFIX}")
```

### Issue: CUDA compilation errors

**Ensure CUDA is properly configured:**
```bash
# Check CUDA path
echo $CUDA_HOME

# Set if not found
export CUDA_HOME=/usr/local/cuda
```

### Issue: `compute_graph_laplacian` crashes or produces incorrect results

**This is the critical bug fixed in 26.6!**

- Upgrade from RAFT 26.04 to 26.6
- Recompile your project with the new libraries
- No API changes required

## Verification Example

Create a test file `test_laplacian.cu`:

```cpp
#include <raft/core/device_resources.hpp>
#include <raft/sparse/linalg/laplacian.cuh>
#include <iostream>

int main() {
  raft::device_resources res;
  
  // Create a simple adjacency matrix (CSR format)
  // ... your sparse matrix setup ...
  
  // Compute Laplacian - this now works correctly on aarch64!
  auto laplacian = raft::sparse::linalg::detail::compute_graph_laplacian(res, adj_matrix);
  
  std::cout << "Laplacian computed successfully!" << std::endl;
  return 0;
}
```

Compile and run:
```bash
nvcc -std=c++20 \
  -I$RAFT_ROOT/include \
  -L$RAFT_ROOT/lib \
  -lraft -lrmm \
  test_laplacian.cu -o test_laplacian

./test_laplacian
```

## Python Wheel Installation (DGX Spark / SM_121 only)

Two wheels are required: `libraft-cu13` (bundles `libraft.so`) and `pylibraft-spark-cu13` (Cython extensions).

```bash
BASE=https://github.com/zbrad/raft/releases/download/v26.06.00-aarch64-cuda132-spark

pip install \
    --extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple \
    "${BASE}/libraft_cu13-26.6.0-py3-none-linux_aarch64.whl" \
    "${BASE}/pylibraft_spark_cu13-26.6.0-cp311-abi3-linux_aarch64.whl"
```

Or add to `requirements.txt`:

```
--extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple
libraft-cu13 @ https://github.com/zbrad/raft/releases/download/v26.06.00-aarch64-cuda132-spark/libraft_cu13-26.6.0-py3-none-linux_aarch64.whl
pylibraft-spark-cu13 @ https://github.com/zbrad/raft/releases/download/v26.06.00-aarch64-cuda132-spark/pylibraft_spark_cu13-26.6.0-cp311-abi3-linux_aarch64.whl
```

> **Note**: `pylibraft-spark-cu13` is compiled for SM_121 only and will not run on other GPU architectures.
> The RAPIDS nightly index is required for `rmm-cu13==26.6.*` and `rapids-logger==0.2.*` runtime dependencies.

## Documentation

For more information, see:
- **Release Notes**: `RELEASE_NOTES_26.6_aarch64.md`
- **API Reference**: https://docs.rapids.ai/api/raft/stable/

## Support

Encountering issues? Check:
1. **Checklist above** - Most issues are environment-related
2. **GitHub Issues** - https://github.com/zbrad/raft/issues
3. **RAFT Documentation** - https://docs.rapids.ai/api/raft/

## Package Contents Summary

| Item | Location | Count |
|------|----------|-------|
| Shared Libraries | `lib/` | 3 files |
| Header Files | `include/` | 2,778 files |
| CMake Configs | `lib/cmake/` | 30+ files |
| **Total Size** | - | **3.2 MB** |

## What's Changed

✅ **Critical Bug Fix**: Sparse Laplacian computation now works correctly on aarch64 with CUDA 13.2  
✅ **64-bit Index Support**: Full support for `NZType=long` in sparse algorithms  
✅ **CCCL 3.4.0 Compatible**: Works with latest NVIDIA CUDA C++ Core Library  

---

**Release**: RAFT 26.6  
**Platform**: aarch64 (Grace Hopper)  
**CUDA**: 13.2+  
**Package**: raft-26.6-aarch64-cuda132.tar.bz2
