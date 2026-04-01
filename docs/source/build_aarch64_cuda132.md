# Building RAFT on aarch64 with CUDA 13.2

This document describes the successful build of RAFT on an aarch64 system (Grace Hopper architecture) with CUDA 13.2 and Python 3.14.3.

## Build Environment

| Component | Version | Details |
|-----------|---------|---------|
| Architecture | aarch64 | ARM-based (Grace Hopper - compute capability 121a) |
| CUDA Toolkit | 13.2.51 | NVIDIA CUDA compiler and libraries |
| Python | 3.14.3 | Python interpreter for Python bindings |
| CMake | 3.30.4 | Build system |
| GCC | 13.3.0 | C/C++ compiler |
| Build Tool | Ninja/Make | Parallel build system |

## Build Instructions

### Prerequisites

Ensure the following are installed:
```bash
# Core build tools
gcc --version      # GCC 13.3.0+
g++ --version      # G++ 13.3.0+
cmake --version    # CMake 3.30.4+
nvcc --version     # CUDA 13.2+

# Python
python3.14 --version    # Python 3.14.3+
python3.14 -m pip list  # Verify pip is available
```

### Install Python Dependencies

```bash
python3.14 -m pip install --user \
  cmake \
  ninja \
  sphinx \
  pytest \
  scipy \
  scikit-learn \
  cython
```

### Build libraft C++

```bash
cd /path/to/raft
./build.sh libraft --compile-lib -v
```

**Build Time**: ~30-45 minutes  
**Output Location**: `cpp/build/install/`

### Build pylibraft (Python wrappers)

**Note**: Python bindings require conda/mamba with RMM and other RAPIDS dependencies. If conda is not available, the C++ libraries can be used directly in downstream projects.

```bash
# With conda environment active:
./build.sh libraft pylibraft --compile-lib -v
```

## Build Results

### ✅ Successful Build Artifacts

#### C++ Libraries
- **libraft.so** (4.49 MB) - Shared library with pre-compiled template instantiations
- **libraft.a** (6.79 MB) - Static library
- **librmm.so** (0.18 MB) - Memory manager
- **librapids_logger.so** (0.64 MB) - Logging support

**Location**: `cpp/build/install/lib/`

#### Headers
- **2,580 header files** covering all RAFT algorithms and primitives
- **Location**: `cpp/build/install/include/raft/`

#### CMake Configuration
- **12 CMake configuration files** for downstream project integration
- **Location**: `cpp/build/install/lib/cmake/raft/`

### Build Log

```bash
# View build output
tail -f build_libraft.log
```

## Environment Configuration

After building, configure your shell environment to use RAFT libraries:

```bash
# Load the CUDA 13.2 environment setup script
source cpp/build/raft_cu132_env.sh
```

This script:
- Configures Python 3.14.3
- Sets up library paths for CUDA 13.2 and RAFT
- Exports CMAKE_PREFIX_PATH for downstream projects
- Creates Python/Pip aliases for python3.14

## Using RAFT in Downstream Projects

### CMake Integration

```cmake
cmake_minimum_required(VERSION 3.26.4 LANGUAGES CXX CUDA)
project(MyProject LANGUAGES CXX CUDA)

# Set RAFT prefix path
set(CMAKE_PREFIX_PATH "/path/to/raft/cpp/build/install")

# Find and link RAFT
find_package(raft REQUIRED)
target_link_libraries(my_target PRIVATE raft::raft)
```

### Compile Command

```bash
cd /path/to/myproject
mkdir build && cd build

cmake \
  -DCMAKE_PREFIX_PATH=/path/to/raft/cpp/build/install \
  -DCMAKE_CXX_STANDARD=20 \
  -DCMAKE_CUDA_STANDARD=20 \
  ..

make -j$(nproc)
```

### Library Path Configuration

```bash
# For runtime, ensure LD_LIBRARY_PATH includes RAFT libraries
export LD_LIBRARY_PATH=/path/to/raft/cpp/build/install/lib:$LD_LIBRARY_PATH
```

## Verifying the Build

### Check Library Symbols

```bash
# Verify library is properly built
ldd cpp/build/install/lib/libraft.so

# Check for key symbols
nm cpp/build/install/lib/libraft.so | grep "device_resources" | head -5
```

### Test CMake Integration

```bash
# Verify CMake can find RAFT
cmake --find-package \
  -DNAME=raft \
  -DCOMPILER_PATH=/usr/bin/cc \
  -DLANGUAGE=C \
  -DMODE=EXIST
```

### Inspect Headers

```bash
# Verify headers are accessible
ls cpp/build/install/include/raft/core/
ls cpp/build/install/include/raft/linalg/
ls cpp/build/install/include/raft/matrix/
```

## Known Issues and Workarounds

### Issue: `python: command not found` during build

**Cause**: build.sh uses `python` command which may not be in PATH

**Workaround**: Create a symlink or alias
```bash
alias python=python3.14
```

### Issue: RMM not available via pip

**Cause**: RMM requires conda for installation

**Workaround**: Install conda/mamba first, then use conda to install dependencies
```bash
# See build.md conda environment section
mamba env create -f conda/environments/all_cuda-131_arch-aarch64.yaml
```

### Issue: Missing NCCL/UCX for distributed builds

**Cause**: raft-dask requires NCCL and UCX

**Workaround**: Install separately or use conda environment
```bash
# With conda:
mamba install -c conda-forge nccl ucx
```

## Performance Considerations

### GPU Architecture Optimization

The build automatically detects and optimizes for Grace Hopper (compute capability 121a). For best performance:

- Ensure CUDA_ARCH is detected correctly: Check build log for "Using auto detection of gpu-archs"
- Verify compilation targeting correct compute capability

### Build Optimization

```bash
# Use ccache/sccache for faster rebuilds
./build.sh libraft --compile-lib --cache-tool=ccache

# Build for all architectures (if needed)
./build.sh libraft --compile-lib --allgpuarch
```

## Next Steps

1. **Use libraft in C++ projects**: Link against libraft.so with CMake
2. **Install Python packages**: When conda is available, install pylibraft and raft-dask
3. **Run benchmarks**: Use cpp/build/MATRIX_PRIMS_BENCH for performance testing
4. **Run tests**: Use cpp/build/*_TEST for verification

## References

- [RAFT Repository](https://github.com/rapidsai/raft)
- [RAFT Documentation](https://docs.rapids.ai/api/raft/stable/)
- [RAPIDS GitHub](https://github.com/rapidsai/)
- [Grace Hopper Architecture](https://www.nvidia.com/en-us/data-center/grace-hopper-superchip/)

## Support

For issues or questions:
- Check [RAFT Issues](https://github.com/rapidsai/raft/issues)
- Review [build.md](./build.md) for detailed build instructions
- Consult [quick_start.md](./quick_start.md) for getting started guide
