# tuned/ — single-arch RAFT builds

Builds RAFT for one GPU variant and one CUDA toolkit, in two forms: the native `libraft` tarball (the C++ library and
its dependencies, which zbrad/cuvs and zbrad/faiss consume) and Python wheels (`libraft`, `pylibraft`, `raft-dask`, plus a
`librmm`/`rmm` pair shared by all variants). The layout and rules are `docs/ARCHITECTURE.md` in
[zbrad/tuned-common](https://github.com/zbrad/tuned-common). Only gb10 is built here today; rtx40 and rtx50 have settings
in `repo.env` and wrapper scripts under `tuned/rtx40/` and `tuned/rtx50/`, but no hardware to test them on.

## Native release

```
CUDA_TAG=cu134 bash tuned/build.sh gb10        # libraft + tests               -> tuned/build/cu134/cmake/
CUDA_TAG=cu134 bash tuned/full_test.sh gb10    # every built gtest binary      -> tuned/build/cu134/releases/ log
CUDA_TAG=cu134 bash tuned/package.sh gb10      # tarball, sha256, DRAFT notes  -> .../dist/
CUDA_TAG=cu134 bash tuned/smoke_test.sh gb10
# review and commit tuned/releases/RELEASE_NOTES_<label>_<variant>_<cuda>.md
CUDA_TAG=cu134 bash tuned/release.sh gb10      # gates only; writes the ready-marker, never publishes
CUDA_TAG=cu134 bash tuned/publish.sh gb10      # publishes exactly what release.sh saw
```

## Wheels

```
CUDA_TAG=cu134 bash tuned/raft_wheel_librmm_shared.sh   # once per toolkit: librmm + rmm, shared by every variant -> .../dist-shared/
CUDA_TAG=cu134 bash tuned/wheel.sh gb10                 # libraft + pylibraft + raft-dask for the variant       -> .../dist/
CUDA_TAG=cu134 bash tuned/wheel_validate.sh gb10        # installs them in a scratch venv and exercises the extensions
```

A wheel release has its own gated flow, the same shape as the native one and independent of it (its tag is the wheels' date
label, `v26.12.0+gb10.cu134.<YYYYMMDD>.<seq>`):

```
CUDA_TAG=cu134 bash tuned/wheel.sh gb10                 # build (also copies in the shared librmm/rmm)  -> .../dist/
CUDA_TAG=cu134 bash tuned/wheel_validate.sh gb10        # install in a scratch venv, exercise the extensions -> TEST_RESULTS_wheels_gb10.log
CUDA_TAG=cu134 bash tuned/wheel_package.sh gb10         # five wheels + sha256 sidecars + DRAFT notes     -> .../dist/release/
CUDA_TAG=cu134 bash tuned/wheel_smoke_test.sh gb10      # the same checks on the packaged files           -> SMOKE_RESULTS_wheels_gb10.log
# review and commit tuned/releases/RELEASE_NOTES_<wheel version>.md
CUDA_TAG=cu134 bash tuned/wheel_release.sh gb10         # gates only; writes the ready-marker, never publishes
CUDA_TAG=cu134 bash tuned/wheel_publish.sh gb10         # publishes exactly what wheel_release.sh saw
```

`wheel.sh` replaces `dist/` (including the native package.sh's output there), so package and release the native tarball first.
`cupy_build.sh` builds a CuPy wheel for the variant's single architecture (smaller than the PyPI wheel, which bundles SASS for every architecture).

## Files

| File | Purpose |
|---|---|
| `env.sh` | device, toolkit and tree setup, including `GPU_TUNED_VENV_DIR`; sourced by every script |
| `repo.env` | raft-only settings |
| `common.sh`, `sync-common.sh`, `common-data/` | vendored from tuned-common; refresh with `bash tuned/sync-common.sh sync` |
| `build.sh`, `full_test.sh`, `package.sh`, `smoke_test.sh`, `release.sh`, `publish.sh` | the native stages above |
| `wheel.sh`, `raft_wheel_librmm_shared.sh`, `raft_wheel_common.sh`, `wheel_validate.sh`, `wheel_package.sh`, `wheel_smoke_test.sh`, `wheel_release.sh`, `wheel_publish.sh`, `cupy_build.sh` | the wheel flow |
| `requirements-build-cuda13x.txt` | build-venv requirements for the wheels (includes `cmake>=4.0` and `ninja`, because the host's CMake is older) |
| `regression_test.sh`, `raft_full_test_monitored.sh`, `raft_monitor.sh`, `raft_sync.sh`, `raft_test_common.sh` | test helpers and monitors |
| `gb10/`, `rtx40/`, `rtx50/` | per-variant wrapper scripts that call the shared implementations |
| `docs/RELEASE_PINS.md` | every published release, the repo commit and the exact `rapids-cmake` commit it was configured against |
| `compliance.conf` | attestations for the checks `tools/tuned_compliance.sh` cannot make mechanically |

## Build venv and gates (wheels)

- The venv is `tuned/build/<cuda-tag>/venv`, made by `gpu_tuned_setup_build_venv`; `GPU_TUNED_CLEAN_VENV=1` recreates it.
  The wheel scripts export `CONDA_PREFIX` as that venv (rapids-build-backend and the `PATH` they set use it); `raft-dask`
  is built without `CONDA_PREFIX`, because the fetched `ucxx` otherwise makes a `conda_env` target its export set rejects.
- The native build stays outside the venv: only steps that run Python use it.
- Each wheel is dependency-audited (H9) and the venv's setuptools is checked (H10, minimum 84.2). Sibling wheels and
  RAPIDS nightly packages are not on PyPI; the audit lists them as "not audited" with the reason.
- The wheel scripts reset `PATH` before sourcing `env.sh`, so the toolkit `PATH` check sees a clean `PATH`.
- The `librmm`/`rmm` version follows the RMM that raft's CMake fetched (26.10 at the time of writing), not raft's own
  version (26.12), because the `libraft` binary must match the RMM it was compiled against.
