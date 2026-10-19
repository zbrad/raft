# RAFT 26.12 — GB10 / DGX Spark (CUDA 13.4) — v0.20261019.0-gb10-cu134

**Package**: `raft-0.20261019.0-gb10-cu134.tar.bz2` · aarch64 · SM_121a · tested and built at `3756ce9e`, packaged at `bdec199d` (only `tuned/` changed in between, which `tuned/package.sh` checks)

## Install

The toolkit is part of the release name: `-cu133` is built with CUDA 13.3, `-cu134` with CUDA 13.4. Set `CUDA_TAG` once and
every command below follows it. This note is for **cu134**; to use the cu133 release set `CUDA_TAG=cu133` (it has its own note and tarball).

```
CUDA_TAG=cu134
TAG=v0.20261019.0-gb10-${CUDA_TAG}
mkdir -p ~/opt && cd ~/opt
gh release download "${TAG}" -R zbrad/raft -p "raft-*-gb10-${CUDA_TAG}.tar.bz2"
sha256sum -c raft-*-gb10-${CUDA_TAG}.tar.bz2.sha256     # if the .sha256 asset was downloaded too
tar xjf raft-*-gb10-${CUDA_TAG}.tar.bz2                  # extracts into raft-0.20261019.0-gb10-${CUDA_TAG}/
```

- **Path:** `~/opt/raft-0.20261019.0-gb10-cu134/` (`lib/`, `include/`, `lib/cmake/`). Use any directory you like.
- **Build against it:** `cmake -Draft_DIR=~/opt/raft-0.20261019.0-gb10-${CUDA_TAG}/lib/cmake/raft ...` (rmm, rapids_logger and nvtx3 are in the same tree).
- **Run:** put the package `lib/` first on `LD_LIBRARY_PATH`. The shared objects use `RUNPATH $ORIGIN`, so the CUDA libraries (`libcudart`, `libcublas`)
  come from your environment: point `LD_LIBRARY_PATH` at the matching toolkit, e.g. `/usr/local/cuda-13.4/lib64` for cu134.
- **Needs:** aarch64, GB10 (SM 12.1), driver R580 or newer.

## Components

| Component | Shipped file | Device code | Tests | Result |
|---|---|---|---|---|
| RAFT 26.12 | `libraft-gb10-cu134.so` | yes (sm_121a) | full suite, 16 gtest binaries | 16/16 passed; 7,648 ran, 7,605 passed, rest skipped |
| rmm | `librmm-cu134.so` | no | covered by the RAFT suite | passed |
| rapids_logger | `librapids_logger-cu134.so` | no | covered by the RAFT suite | passed |
| nvtx3 | headers + CMake config | no | consumer configure against the package alone | passed (packaging gate) |
| Package as extracted | `raft-0.20261019.0-gb10-cu134.tar.bz2` | | smoke: 3 binaries (`CORE_TEST_NOCUDA` 23, `MATRIX_SELECT_TEST` 599 / 81 skipped, `UTILS_TEST` 237) | passed |

## This release

Rebuilt in the flat per-toolkit tree (`tuned/build/cu134/`, no variant level) with shared objects named by their axes
(tuned-common `docs/ARCHITECTURE.md`). **Breaking rename for anything that loaded the earlier `-tuned` names by file name:**

| Earlier (v0.20261015.0) | This release |
|---|---|
| `librmm-tuned.so` | `librmm-cu134.so` (no device code: toolkit axis only) |
| `librapids_logger-tuned.so` | `librapids_logger-cu134.so` |
| `libraft-gb10-cu134.so` | unchanged (device code: variant and toolkit) |

File name, SONAME and every `DT_NEEDED` follow the new names, and the installed CMake import files point at them, so
`find_package(raft)` consumers relink without edits. Rebuild consumers built against the earlier names (zbrad/cuvs and zbrad/faiss, whose
matching releases follow). Packaging fails closed unless every shared object carries the right axes.

**Supersedes** `v0.20261015.0-gb10-cu134`, which carries the earlier `-tuned` shared-object names and stays published for consumers that pin its URL.

## Tested

- Full suite (`tuned/full_test.sh`, 2026-10-18, 22:29Z–22:50Z): **16/16 gtest binaries passed**; 7,648 tests ran, 7,605 passed, the rest skipped (log attached).
- Smoke-tested as packaged: the tarball was extracted and checked on its own (`MATRIX_SELECT_TEST` 599 tests, 81 skipped; `UTILS_TEST` 237 tests); `librmm-cu134.so`, `librapids_logger-cu134.so`
  and `libraft-gb10-cu134.so` resolve to files inside the package (log attached). Three binaries, not the suite.

**Not in this release:** the Python wheels (build/validate only, not published).
