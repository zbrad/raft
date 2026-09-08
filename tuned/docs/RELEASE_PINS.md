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
| `v26.10-gb10-cu133-g56f094c7` | [`56f094c7`](https://github.com/zbrad/raft/commit/56f094c7) | [`8fc2d05e`](https://github.com/rapidsai/rapids-cmake/commit/8fc2d05e4b29a2fb7a355192ce19190fcf24c37f) ([zip](https://github.com/rapidsai/rapids-cmake/archive/8fc2d05e4b29a2fb7a355192ce19190fcf24c37f.zip)) | 2026-09-08 | First pinned build. Supersedes `v26.10-gb10-cu133` (Aug 7, deleted — same tag, unpinned, predates the laplacian NZType fix and this whole pinning mechanism). Laplacian fix (`NVIDIA/raft#3141`) + full test suite (237 tests, 16/16 binaries, 0 failures) attached as a release asset. |
