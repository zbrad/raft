# RAFT 26.6 Release - Complete Index

**Release Date**: April 6, 2026  
**Platform**: aarch64 (NVIDIA GB10 / DGX Spark)  
**CUDA Version**: 13.2+  
**GPU Architecture**: SM_121 (GB10 / Grace Blackwell)

---

## 📦 Release Deliverables

### 1. C++ Binary Package
**File**: `raft-26.6-aarch64-cuda132.tar.bz2` (3.2 MB)

The complete pre-compiled RAFT library for aarch64 systems with CUDA 13.2.

**Contents**:
- Shared libraries (libraft.so, librmm.so, librapids_logger.so)
- 2,778+ header files for RAFT, RMM, and logging
- 30+ CMake configuration files for seamless integration
- Total: 2,832 files

**Use When**: You need the pre-compiled libraries ready to use in your project.

```bash
tar -xjf raft-26.6-aarch64-cuda132.tar.bz2
```

---

### 2. Python Wheels (DGX Spark / SM_121 only)

**Files**:
- `libraft_cu13-26.6.0-py3-none-linux_aarch64.whl` (3.3 MB) — C++ runtime, bundles `libraft.so`
- `pylibraft_spark_cu13-26.6.0-cp311-abi3-linux_aarch64.whl` (336 KB) — Cython extensions

**Use When**: You need to use RAFT from Python on a DGX Spark (SM_121).

> These wheels target SM_121 **only** and will not run on other GPU architectures.
> `pylibraft-spark-cu13` is named separately from `pylibraft-cu13` to prevent accidental installation
> on incompatible hardware. See `RELEASE_NOTES_26.6_aarch64.md` for the full naming rationale.

```bash
BASE=https://github.com/zbrad/raft/releases/download/v26.06.00-aarch64-cuda132-spark
pip install \
    --extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple \
    "${BASE}/libraft_cu13-26.6.0-py3-none-linux_aarch64.whl" \
    "${BASE}/pylibraft_spark_cu13-26.6.0-cp311-abi3-linux_aarch64.whl"
```

---

### 3. Checksum File
**File**: `CHECKSUMS`

Checksums for verifying package integrity.

**Contents**:
- SHA256 checksum (recommended)
- MD5 checksum (for compatibility)

**Use When**: Verifying the downloaded package hasn't been corrupted or tampered with.

```bash
sha256sum -c CHECKSUMS
```

---

## 📚 Documentation

### 4. Release README
**File**: `RELEASE_README_26.6_aarch64.md`

**For**: Quick orientation and overview  
**Contains**:
- What's new in RAFT 26.6
- Hardware support matrix
- Package contents summary
- Testing & validation results
- Quick start (3 steps to get running)

**Read This First** if you want a high-level understanding of the release.

---

### 5. Release Notes
**File**: `RELEASE_NOTES_26.6_aarch64.md`

**For**: Detailed technical information  
**Contains**:
- Complete description of the critical fix
  - Root cause analysis
  - What was changed (with before/after code)
  - Why it matters
- CUDA and compiler requirements
- Complete hardware support list
- Build environment specifications
- Performance considerations
- Known issues (none reported)

**Read This If**: You need to understand the technical details of the fix, or integrating RAFT into a larger system.

---

### 6. Installation Guide
**File**: `INSTALL_GUIDE_26.6_aarch64.md`

**For**: Getting RAFT up and running  
**Contains**:
- Prerequisites checklist
- Step-by-step installation (4 steps)
- Environment variable setup
- CMake project integration examples
- Manual compilation instructions
- Troubleshooting guide
- Verification example code

**Read This If**: You're ready to install and use RAFT in your project.

---

## 🎯 Which Document Should I Read?

```
┌─ I want a quick overview
│  └─> Read: RELEASE_README_26.6_aarch64.md (5 min)
│
├─ I need to install RAFT
│  └─> Read: INSTALL_GUIDE_26.6_aarch64.md (10 min)
│
├─ I want technical details about the fix
│  └─> Read: RELEASE_NOTES_26.6_aarch64.md (15 min)
│
├─ I need to verify package integrity
│  └─> Check: CHECKSUMS (1 min)
│
└─ I'm looking for CMake integration examples
   └─> Read: INSTALL_GUIDE_26.6_aarch64.md → Option A
```

---

## 📋 Document Summary Table

| Document | Purpose | Audience |
|----------|---------|----------|
| RELEASE_README_26.6_aarch64.md | Overview & quick start | Everyone |
| RELEASE_NOTES_26.6_aarch64.md | Technical details & fix explanation | Developers, integrators |
| INSTALL_GUIDE_26.6_aarch64.md | Step-by-step installation (C++ and Python) | Users setting up RAFT |
| CHECKSUMS | Verify package integrity | Security-conscious users |
| raft-26.6-aarch64-cuda132.tar.bz2 | C++ binary package | C++/CUDA projects |
| libraft_cu13-26.6.0-*.whl | C++ runtime wheel | Python on DGX Spark |
| pylibraft_spark_cu13-26.6.0-*.whl | Python wheel | Python on DGX Spark |

---

## 🚀 Quick Path: From Release to Running Code

```
Step 1: Overview
  └─> Read: RELEASE_README_26.6_aarch64.md

Step 2: Install
  └─> Read: INSTALL_GUIDE_26.6_aarch64.md
  └─> tar -xjf raft-26.6-aarch64-cuda132.tar.bz2
  └─> source setup-raft.sh  (or manual env setup)

Step 3: Integrate
  └─> Follow CMake example in INSTALL_GUIDE_26.6_aarch64.md
  └─> cmake -DCMAKE_PREFIX_PATH=$RAFT_ROOT ..

Step 4: Run Tests (optional)
  └─> Follow verification example in INSTALL_GUIDE_26.6_aarch64.md
  └─> ./test_laplacian

Total Time: ~20-30 minutes
```

---

## 🔍 Key Information at a Glance

### Critical Fix Details
**File Affected**: `raft/sparse/linalg/detail/laplacian.cuh`  
**Lines Changed**: 129-130  
**Change**: `int` → `NZType`  
**Impact**: Fixes CUDA context corruption on aarch64 with CCCL 3.4.0  
**See**: RELEASE_NOTES_26.6.md (section "Critical Fix")

### Hardware Support
- ✅ **Grace Hopper** (SM_121a, aarch64) - Primary support
- ✅ Other aarch64 systems with NVIDIA GPUs
- ❌ x86-64 systems (continue with RAFT 26.04)

### Test Results
- **Total Tests**: 483
- **Passed**: 483 ✅
- **Failed**: 0
- **Runtime**: ~514 seconds

### Package Contents
- Libraries: 3 shared objects
- Headers: 2,778+ files
- CMake Configs: 30+ files
- Total Files: 2,832
- Total Size: 3.2 MB

---

## 💾 File Locations

All release files are located in the repository root:

```
/home/zbrad/gh/raft/
├── RELEASE_INDEX_26.6_aarch64.md           (this file)
├── RELEASE_README_26.6_aarch64.md          (start here!)
├── RELEASE_NOTES_26.6_aarch64.md           (detailed info)
├── INSTALL_GUIDE_26.6_aarch64.md           (how to install)
├── CHECKSUMS                               (verify integrity)
├── raft-26.6-aarch64-cuda132.tar.bz2      (C++ package)
└── dist/spark/                             (Python wheels)
    ├── libraft_cu13-26.6.0-py3-none-linux_aarch64.whl
    └── pylibraft_spark_cu13-26.6.0-cp311-abi3-linux_aarch64.whl
```

---

## ✅ Pre-Download Checklist

Before using this release, verify:

- [ ] System is aarch64 architecture (`uname -m` returns aarch64)
- [ ] CUDA 13.2+ is installed (`nvcc --version` shows 13.2+)
- [ ] GPU is Grace Hopper (`nvidia-smi --query-gpu=compute_cap` shows 12.1)
- [ ] CMake 3.26.4+ available (`cmake --version`)
- [ ] C++ compiler available (GCC 13.3.0+ preferred)

See INSTALL_GUIDE_26.6.md for detailed verification steps.

---

## 🆘 If Something Goes Wrong

1. **Installation issues?**
   - See INSTALL_GUIDE_26.6.md → Troubleshooting section

2. **Want technical details?**
   - See RELEASE_NOTES_26.6.md → Know Issues & Compatibility

3. **Still stuck?**
   - Report at: https://github.com/rapidsai/raft/issues
   - Include: CUDA version, GPU architecture, error message

---

## 📖 Related Documentation

In the RAFT repository:
- **docs/source/build_aarch64_cuda132.md** - Full build guide (if you want to build from source)
- **docs/source/build.md** - General build instructions
- **README.md** - RAFT project overview
- https://docs.rapids.ai/api/raft - Online API documentation

---

## 📝 Version Information

| Component | Version |
|-----------|---------|
| RAFT | 26.6 |
| CUDA Toolkit | 13.2.51 |
| CCCL | 3.4.0 |
| RMM | 26.06 |
| GCC (tested) | 13.3.0 |
| CMake (tested) | 3.30.4 |
| Architecture | aarch64 |
| GPU Arch | SM_121a |

---

## 🎯 Next Steps

**Choose one**:

```
Option A: I want a quick overview
└─> cat RELEASE_README_26.6_aarch64.md

Option B: I want to start installing
└─> cat INSTALL_GUIDE_26.6_aarch64.md

Option C: I want detailed technical info
└─> cat RELEASE_NOTES_26.6_aarch64.md

Option D: I want to verify the package
└─> sha256sum -c CHECKSUMS
```

---

**RAFT 26.6 Release**  
March 31, 2026  
Platform: aarch64 (Grace Hopper)  
CUDA: 13.2+  
Status: ✅ Ready for production use
