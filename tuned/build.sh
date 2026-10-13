#!/bin/bash
# build.sh <variant> — build libraft + tests for the given GPU
# variant (gb10/rtx40/rtx50). Shared implementation behind every
# gb10/rtx40/rtx50 raft_build_<variant>.sh wrapper.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GPU_TUNED_ARG_VARIANT="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1
cd "${PROJECT_ROOT}"

# raft-<variant>-<cuda_tag>, matching zbrad/cuvs's libcuvs-<variant>-<tag>.so
# naming (tuned/build.sh's CUVS_LIB_NAME there) -- see cpp/CMakeLists.txt's
# RAFT_OUTPUT_NAME override, and tuned/wheel.sh, which shares this build
# dir/CMakeCache and has been updated to expect this name too (not the bare
# "libraft.so" it used to look for).
RAFT_LIB_NAME="raft-${GPU_TUNED_VARIANT}-${CUDA_TAG}"

# rapids-cmake-sha: pin to a fixed commit instead of letting RAPIDS.cmake
# fall through to RAPIDS_BRANCH ("main", an upstream file -- don't edit
# it, it'll just get overwritten on the next upstream sync anyway).
# RAPIDS.cmake's own precedence rules give an explicit -Drapids-cmake-sha
# priority over the branch, so this is the supported override point, not
# a hack. Without this, two builds done at different times can silently
# resolve different transitive dependency versions (rapids-cmake's own
# pins move on its unpinned main) -- confirmed 2026-09-08: raft and cuvs
# builds a few hours apart disagreed on rapids_logger (0.2.3 vs 0.3.0),
# breaking cuvs's configure (duplicate ALIAS target) since it links
# against raft's published/local install tree either way.
#
# Sibling pin: zbrad/cuvs's tuned/build.sh carries the identical SHA --
# keep both in sync by hand when bumping (grep RAPIDS_CMAKE_PIN_SHA in
# each repo's tuned/build.sh). Update by picking a fresh
# `git ls-remote https://github.com/rapidsai/rapids-cmake.git main`
# HEAD, confirming both repos still configure cleanly against it, then
# updating both files together in the same sitting -- never one without
# the other, that's exactly the drift this exists to prevent.
# 2026-10-12: moved from 8fc2d05e (2026-09-08) to 61a96c8f, rapids-cmake's "Update cuco for
# RoaringBitmap use in cuVS (#1095)". cuVS's roaring-bitmap CAGRA filter (#2446) calls
# cuco::roaring_bitmap::from_indices, which the older pinned cuco lacks. Exactly two packages differ
# between the two pins: cuco 4b26118c -> 8ed532dc, and CCCL (labelled 3.5.0 in both) 399863ef ->
# b98d4bd6, so raft was rebuilt, retested and republished with the same pin.
RAPIDS_CMAKE_PIN_SHA="61a96c8f29731affd7fd913a586673dd057dc3b0"

BUILD_DIR="$(gpu_tuned_out_dir build "${PROJECT_ROOT}" "${CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
gpu_tuned_assert_cmake_cache_consistent "${BUILD_DIR}" || exit 1

# Timing: ninja appends to this log across runs, so only what lands after this point is this build.
NINJA_LOG="${BUILD_DIR}/.ninja_log"
NINJA_OFFSET=0
[[ -f "${NINJA_LOG}" ]] && NINJA_OFFSET="$(wc -c < "${NINJA_LOG}")"
BUILD_T0="${EPOCHSECONDS}"
ccache -z >/dev/null 2>&1 || true

# Unique shared-object identities at build time: the fetched librmm and librapids_logger get
# OUTPUT_NAME <name>-tuned through a CMake include (no upstream source is edited), so the build tree,
# the install tree, every DT_NEEDED and the CMake export files all carry the names we ship.
# The install tree (below) must not be found by the next configure: a cached rmm_DIR/rapids_logger_DIR
# pointing into it makes CMake use the installed copies instead of building the dependencies, so the
# renamed targets would not exist. Hence the ignored prefix and the two -U. The pip wheels in the user
# site-packages are ignored too: they ship CMake packages (nvtx3, rmm ...) that CMake would find instead
# of fetching, so nvtx3 would not be installed with our package.
SO_NAMES_CMAKE="${GPU_TUNED_BUILD_ROOT}/so_names.cmake"
gpu_tuned_so_names_cmake "${SO_NAMES_CMAKE}" || exit 1

LIBRAFT_BUILD_DIR="${BUILD_DIR}" bash build.sh libraft tests --compile-lib --cache-tool=ccache "--cmake-args=\"-DCMAKE_CUDA_ARCHITECTURES=${GPU_TUNED_CUDA_ARCH} -DRAFT_OUTPUT_NAME=${RAFT_LIB_NAME} -Drapids-cmake-sha=${RAPIDS_CMAKE_PIN_SHA} -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${SO_NAMES_CMAKE} -DTUNED_SO_TARGETS=rmm;rapids_logger -DCMAKE_IGNORE_PREFIX_PATH=${BUILD_DIR}/install;$(gpu_tuned_cmake_ignore_pip_prefixes) -Urmm_DIR -Urapids_logger_DIR -Unvtx3_DIR\""

# Completeness gate. Upstream's build.sh exits 0 even when a test target fails to compile (a
# release was nearly published with UTILS_TEST silently missing), and tuned/full_test.sh only runs
# the binaries that exist, so a broken target would simply not be tested. A ninja dry run lists what
# is still pending: any compile step, or a link whose executable does not exist, means a target did
# not build. (Re-links of existing test binaries after build-info is stamped into the library are
# normal and are not failures.)
PENDING_BAD="$(cmake --build "${BUILD_DIR}" --target all -- -n 2>&1 | while IFS= read -r line; do
    case "${line}" in
        *"Building "*) echo "${line}" ;;
        *"Linking "*" executable "*) [[ -e "${BUILD_DIR}/${line##* }" ]] || echo "${line}" ;;
    esac
done)"
if [[ -n "${PENDING_BAD}" ]]; then
    echo "ERROR: the build is incomplete -- a target failed to compile or link (upstream's build.sh did not fail):" >&2
    printf '%s\n' "${PENDING_BAD}" | head -10 | sed 's/^/  /' >&2
    exit 1
fi

echo ""
echo "Build timing (wall $(( EPOCHSECONDS - BUILD_T0 ))s):"
if [[ -f "${NINJA_LOG}" ]] && gpu_tuned_ninja_timing "${NINJA_LOG}" "${NINJA_OFFSET}" "${GPU_TUNED_BUILD_ROOT}/timing.tsv" "CMakeFiles/"; then
    echo "  per-target timings: ${GPU_TUNED_BUILD_ROOT}/timing.tsv"
else
    echo "  (no per-target timings: nothing was rebuilt, or ninja logged nothing)"
fi
command -v ccache >/dev/null 2>&1 && echo "ccache: $(ccache -s | grep -E 'Hits:|Misses:' | head -2 | tr -s ' ' | tr '\n' ' ')"

# The install tree (tuned/package.sh copies <build>/install). Upstream's build step did not leave one
# here; the prefix is baked into the CMake cache, so this is an idempotent copy.
# Start from an empty install tree: cmake --install only adds files, so libraries installed by an earlier
# build under a different name (the stock librmm.so before the -tuned rename) would be packaged alongside.
[[ "${BUILD_DIR}/install" == "${PROJECT_ROOT}/tuned/build/"*/cmake/install ]] || { echo "ERROR: unexpected install dir ${BUILD_DIR}/install" >&2; exit 1; }
rm -rf "${BUILD_DIR}/install"
cmake --install "${BUILD_DIR}" >/dev/null || { echo "ERROR: cmake --install failed in ${BUILD_DIR}" >&2; exit 1; }
[[ -f "${BUILD_DIR}/install/lib/lib${RAFT_LIB_NAME}.so" ]] || { echo "ERROR: install produced no lib${RAFT_LIB_NAME}.so under ${BUILD_DIR}/install/lib" >&2; exit 1; }
for _so in librmm-tuned.so librapids_logger-tuned.so; do
    [[ -f "${BUILD_DIR}/install/lib/${_so}" ]] || { echo "ERROR: install produced no ${_so} under ${BUILD_DIR}/install/lib (the build-time rename did not take effect)" >&2; exit 1; }
done
unset _so

gpu_tuned_verify_arch "${BUILD_DIR}/lib${RAFT_LIB_NAME}.so" "${GPU_TUNED_CUDA_ARCH}" || exit 1

# CCCL 3.4.0 is the minimum that includes the warpspeed-scan fixes needed
# to avoid a real memory-corruption bug on Blackwell/SM_12x -- see
# gpu_tuned_verify_cccl_version's own comment in tuned/common.sh for the
# full story (this repo's own NVIDIA/raft#3141, closed once verified
# unnecessary against current CCCL). A hard gate, not informational: an
# old CCCL here means a real, previously-hit corruption bug, not just a
# version mismatch.
gpu_tuned_verify_cccl_version "${BUILD_DIR}/_deps/cccl-src" "3.4.0" || exit 1

# Embed a build-info string into a custom ELF section on the variant-
# qualified copy (readable later via `readelf -p .raft_build_info <lib>`
# or plain `strings`), so which CUDA 13.x *minor* toolkit (and which repo
# fork/commit) built this specific .so is recoverable even if the file
# gets copied/renamed away from its wheel/VERSION metadata. Full ISO-8601
# UTC timestamp, not just a date -- see CLAUDE.md's memory-timestamp
# convention for why bare dates aren't enough (multiple builds can land
# the same day).
BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
GIT_COMMIT="$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
BUILD_INFO_FILE="$(mktemp)"
echo "raft-${GPU_TUNED_VARIANT} build: https://github.com/zbrad/raft @ ${GIT_COMMIT}, CUDA ${CUDA_VERSION}, sm_${GPU_TUNED_CUDA_ARCH}, built ${BUILD_TIMESTAMP}, rapids-cmake @ ${RAPIDS_CMAKE_PIN_SHA}" > "${BUILD_INFO_FILE}"
objcopy --add-section .raft_build_info="${BUILD_INFO_FILE}" "${BUILD_DIR}/lib${RAFT_LIB_NAME}.so"
rm -f "${BUILD_INFO_FILE}"
