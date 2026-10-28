# RAFT 26.12.0 Python wheels — GB10 / DGX Spark (CUDA 13.4) — v26.12.0+gb10.cu134.20261028.1

**Wheels**: `libraft_gb10_cu13`, `pylibraft_gb10_cu13`, `raft_dask_gb10_cu13` (all `26.12.0+gb10.cu134.20261028.1`) and the shared
`librmm_cu13`, `rmm_cu13` (`26.10.0+shared.cu134.20261027.0`) · aarch64 · SM_121a · Python 3.11+ (`abi3`) · built at the commit the
packaging step recorded. The native C++ package has its own release, `v0.20261028.0-gb10-cu134`; the two are independent.

## Install

Download all five wheels into one directory and install them together, so pip takes `librmm`/`rmm` from here and not from PyPI:

```
gh release download v26.12.0+gb10.cu134.20261028.1 -R zbrad/raft -p '*.whl' -D raft-wheels
pip install raft-wheels/*.whl
```

- The dependencies that are not ours (`dask-cuda`, `libucx-cu13`, `nvidia-nccl-cu13`, `cuda-toolkit`) come from PyPI. The RAPIDS
  nightly index is needed for `rapids-dask-dependency`; install with
  `--extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple --prerelease=allow` if pip cannot resolve it.
- **Needs:** aarch64, GB10 (SM 12.1), driver R580 or newer.

## What these are

| Wheel | Contains | Notes |
|---|---|---|
| `libraft-gb10-cu13` | `libraft_gb10_cu134.so`, single-arch `sm_121a` | build info stamped in the library; the name cannot collide with RAPIDS's `libraft-cu13` |
| `pylibraft-gb10-cu13` | Cython bindings for the above | |
| `raft-dask-gb10-cu13` | `raft_dask` comms (NCCL) | the bundled extensions load the pip `nvidia-nccl-cu13` |
| `librmm-cu13`, `rmm-cu13` | RMM 26.10 (the RMM raft's CMake fetched), with `librapids_logger` | no device code, so one build serves every GPU variant |

## This release

First release of these wheels as a gated release; earlier builds were local only.

- The version carries the tuned date label (`+gb10.cu134.<YYYYMMDD>.<seq>`) like every other tuned wheel.
- **Floors for a single-toolkit build.** `libraft` requires `cuda-toolkit` and `nvidia-nvjitlink` at 13.4 or later (upstream allows any 13.x),
  and `raft-dask` requires `nvidia-nccl-cu13` 2.32.3 or later, the first build made for CUDA 13.4 (upstream's floor is 2.19).
- `libucx-cu13` is `>=1.19.0,<1.19.1`, as upstream pins it.

## Tested

- Validation (`tuned/wheel_validate.sh`): the wheels install in a fresh Python 3.14 venv; `pylibraft` runs a real `Handle()` in its compiled
  extension, `raft_dask` imports its comms, and the loaded `libraft` identifies itself as `gb10` (log attached).
- Smoke test (`tuned/wheel_smoke_test.sh`): the same checks on the packaged files, after their sha256 sidecars were verified (log attached).
- Each wheel's runtime dependencies were audited for known vulnerabilities (`pip-audit`); our own sibling wheels are listed as not audited
  because they are not on PyPI.

**Not tested here:** the RAFT C++ test suite (that is the native release's), multi-GPU NCCL paths (one GPU on the build node).
