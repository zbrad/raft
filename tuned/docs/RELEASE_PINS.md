# Release Pins

Tracks every published `tuned-builds` release: which repo commit it was
built from, and which exact `rapids-cmake` commit it was configured
against (`-Drapids-cmake-sha=...`, see `tuned/build.sh`). Update this
table as part of publishing a release — add a row before or right after
running `tuned/release.sh`.

Why this exists: `rapids-cmake` is fetched unpinned by default
(`RAPIDS.cmake` falls through to `RAPIDS_BRANCH`, which upstream sets to
`main` — an always-moving target). Two builds done at different times can
silently resolve different transitive dependency versions from it (hit
for real 2026-09-08: raft and `zbrad/cuvs` builds a few hours apart
disagreed on `rapids_logger` 0.2.3 vs 0.3.0, breaking cuvs's configure).
Pinning `rapids-cmake-sha` in `tuned/build.sh` fixes new builds; this
table is how anyone — including a future session — can look at an
already-published release and know exactly what it was built against, or
reproduce it later without re-deriving anything.

To fetch the exact rapids-cmake source a row references:
```
https://github.com/rapidsai/rapids-cmake/archive/<rapids-cmake sha>.zip
```
(the same URL `-Drapids-cmake-sha=<sha>` causes `RAPIDS.cmake` to fetch
internally — see that file's `rapids-cmake-value-to-clone` logic).

| Release tag | Commit (this repo) | rapids-cmake pin | Date | Notes |
|---|---|---|---|---|
| `v26.10-gb10-cu133-g37ba10e2` | [`37ba10e2`](https://github.com/zbrad/raft/commit/37ba10e2) | [`8fc2d05e`](https://github.com/rapidsai/rapids-cmake/commit/8fc2d05e4b29a2fb7a355192ce19190fcf24c37f) ([zip](https://github.com/rapidsai/rapids-cmake/archive/8fc2d05e4b29a2fb7a355192ce19190fcf24c37f.zip)) | 2026-09-08 | First pinned build. Supersedes `v26.10-gb10-cu133` (Aug 7, deleted — same tag, unpinned, predates the laplacian NZType fix and this whole pinning mechanism). Laplacian fix (`NVIDIA/raft#3141`) + full test suite (237 tests, 16/16 binaries, 0 failures) attached as a release asset. rapids_logger resolved to 0.3.0 (was 0.2.3 in an intermediate same-day build before the pin landed — that one was never published). |
| `v26.12-gb10-cu134-g9d97792e` | [`9d97792e`](https://github.com/zbrad/raft/commit/9d97792e) | [`8fc2d05e`](https://github.com/rapidsai/rapids-cmake/commit/8fc2d05e4b29a2fb7a355192ce19190fcf24c37f) ([zip](https://github.com/rapidsai/rapids-cmake/archive/8fc2d05e4b29a2fb7a355192ce19190fcf24c37f.zip)) | 2026-09-18 | First CUDA 13.4 build (CCCL 3.5.0, upstream's `cuda::stream_ref` migration). Includes the fork-local laplacian `coo_sort` call fix in `9d97792e`. `v26.10-gb10-cu133-g37ba10e2` stays published. |
| `v26.12-gb10-cu133-g9fcf3a1f` | [`9fcf3a1f`](https://github.com/zbrad/raft/commit/9fcf3a1f) | [`8fc2d05e`](https://github.com/rapidsai/rapids-cmake/commit/8fc2d05e4b29a2fb7a355192ce19190fcf24c37f) ([zip](https://github.com/rapidsai/rapids-cmake/archive/8fc2d05e4b29a2fb7a355192ce19190fcf24c37f.zip)) | 2026-09-21 | CUDA 13.3.73 build of the same 26.12 library source as `v26.12-gb10-cu134-g9d97792e` (CCCL 3.5.0). Development build: merged with upstream `main` at `f197acbc`, untagged upstream. 16/16 gtest binaries. cuVS pairing: pending, cuVS cu133 not yet published. |
| `v26.12-rtx40-cu134-ge27a5e00` | [`e27a5e00`](https://github.com/zbrad/raft/commit/e27a5e00) | [`8fc2d05e`](https://github.com/rapidsai/rapids-cmake/commit/8fc2d05e4b29a2fb7a355192ce19190fcf24c37f) ([zip](https://github.com/rapidsai/rapids-cmake/archive/8fc2d05e4b29a2fb7a355192ce19190fcf24c37f.zip)) | 2026-09-19 | RTX 40 (SM_89), x86_64, built and tested on WSL2 (Ubuntu 24.04). `Raft.InterruptibleOpenMP` is skipped under WSL2 only; see `RELEASE_NOTES_26.12_rtx40_cu134.md`. |
| `v26.12-gb10-cu134-ga57c8910` | [`a57c8910`](https://github.com/zbrad/raft/commit/a57c8910) | [`8fc2d05e`](https://github.com/rapidsai/rapids-cmake/commit/8fc2d05e4b29a2fb7a355192ce19190fcf24c37f) ([zip](https://github.com/rapidsai/rapids-cmake/archive/8fc2d05e4b29a2fb7a355192ce19190fcf24c37f.zip)) | 2026-09-22 | Rebuild of the same 26.12 library source as `v26.12-gb10-cu134-g9d97792e` (no cpp/ diff) under the new CUDA-version-distinct output-dir layout. 16/16 gtest binaries. cuVS pairing: pending, cuVS cu134 not yet rebuilt against this release. |
