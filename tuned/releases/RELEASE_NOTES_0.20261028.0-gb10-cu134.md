# RAFT 26.12 — GB10 / DGX Spark (CUDA 13.4) — v0.20261028.0-gb10-cu134

**Package**: `raft-0.20261028.0-gb10-cu134.tar.bz2` · aarch64 · SM_121a · built and tested at `afbba0ab` (only `tuned/` changed afterwards, which `tuned/package.sh` checks)

## Install

Same as the previous cu134 release; set `CUDA_TAG=cu134` and `TAG=v0.20261028.0-gb10-${CUDA_TAG}`:

```
CUDA_TAG=cu134
TAG=v0.20261028.0-gb10-${CUDA_TAG}
mkdir -p ~/opt && cd ~/opt
gh release download "${TAG}" -R zbrad/raft -p "raft-*-gb10-${CUDA_TAG}.tar.bz2"
sha256sum -c raft-*-gb10-${CUDA_TAG}.tar.bz2.sha256     # if the .sha256 asset was downloaded too
tar xjf raft-*-gb10-${CUDA_TAG}.tar.bz2                  # extracts into raft-0.20261028.0-gb10-${CUDA_TAG}/
```

- **Build against it:** `cmake -Draft_DIR=~/opt/raft-0.20261028.0-gb10-${CUDA_TAG}/lib/cmake/raft ...`. The installed CMake config files need **CMake 4.0 or newer**.
- **Run:** put the package `lib/` first on `LD_LIBRARY_PATH` and point it at the matching toolkit (`/usr/local/cuda-13.4/lib64`); the libraries use `RUNPATH $ORIGIN`.
- **Needs:** aarch64, GB10 (SM 12.1), driver R580 or newer.

## Components

| Component | Shipped file | Device code | Tests | Result |
|---|---|---|---|---|
| RAFT 26.12 | `libraft-gb10-cu134.so` | yes (sm_121a) | full suite, 16 gtest binaries | 16/16 passed; 7,605 tests passed |
| rmm | `librmm-cu134.so` | no | covered by the RAFT suite | passed |
| rapids_logger | `librapids_logger-cu134.so` | no | covered by the RAFT suite | passed |
| nvtx3 | headers + CMake config | no | consumer configure against the package alone | passed (packaging gate) |
| Package as extracted | `raft-0.20261028.0-gb10-cu134.tar.bz2` | | smoke: 3 binaries (`CORE_TEST_NOCUDA` 23, `MATRIX_SELECT_TEST` 599 / 81 skipped, `UTILS_TEST` 237) | passed |

## This release

A rebuild of the same RAFT 26.12 library and the same shared-object names as `v0.20261019.0-gb10-cu134`, built with the
toolkit's build venv (CMake 4, Ninja, setuptools 84.2) and the tuned-common gates for it. The build, package and smoke scripts
now take CMake 4 and Ninja from that venv because the host's CMake is 3.30.

**Supersedes** `v0.20261019.0-gb10-cu134`, which stays published for consumers that pin its URL.

## Tested

- Full suite (`tuned/full_test.sh`, 2026-10-28, 07:48Z–08:09Z): **16/16 gtest binaries passed**, 7,605 tests passed (log attached).
- Smoke-tested as packaged: the tarball was extracted and checked on its own; `librmm-cu134.so`, `librapids_logger-cu134.so` and
  `libraft-gb10-cu134.so` resolve to files inside the package (log attached). Three binaries, not the suite.

**Not in this release:** the Python wheels (build only, not published).
