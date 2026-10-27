#!/bin/bash
# raft_wheel_librmm_shared.sh — build librmm-cu13 + rmm-cu13 ONCE, shared
# across every GPU-architecture variant (gb10/rtx40/rtx50). Builds only: it
# publishes nothing (a wheel release is its own, gated step, like a native one).
#
# Run it inside a DEDICATED virtualenv, never your everyday Python: it
# `pip install`s the build requirements and force-reinstalls nothing outside
# the environment it runs in. Point CONDA_PREFIX at the venv (this script puts
# ${CONDA_PREFIX}/bin first on PATH, ahead of ~/.local/bin):
#   uv venv /path/to/venv --python 3.14
#   CONDA_PREFIX=/path/to/venv CUDA_TAG=cu133 bash tuned/raft_wheel_librmm_shared.sh
#
# The toolkit is named (CUDA_TAG=cu133 or CUDA_VER=13.3), never found by
# scanning /usr/local or by nvcc on PATH. SOURCE_ARCH names the variant whose
# build tree supplies rmm (default gb10 on aarch64; on x86_64 name it); the
# CPM-fetched RMM commit is driven by rapids-cmake/the raft commit, not by GPU
# arch flags, so any built variant gives the same rmm.
#
# Why shared, not per-variant: librmm and librapids_logger contain NO device
# code (`cuobjdump --list-elf`: "does not contain device code"; checked below),
# unlike libraft/pylibraft/raft-dask which differ per SM architecture, so one
# build is ABI-correct for every GPU variant. They carry the TOOLKIT in their
# names, librmm-<toolkit>.so and librapids_logger-<toolkit>.so (docs/
# ARCHITECTURE.md F1): file name, SONAME and every DT_NEEDED. The toolkit stays
# in the name because the package ships CCCL-typed headers and was compiled with
# that toolkit's CCCL (decisions/2026-10-17-shared-object-names-carry-their-axes.md).
#
# Both libraries are bundled in the librmm wheel: the stock rapids-logger wheel
# ships librapids_logger.so under the stock name, which our librmm does not NEED,
# so the wheel no longer depends on it and its loader loads our bundled logger
# first.
#
# Distribution names stay PLAIN ("librmm-cu13"/"rmm-cu13", matching upstream);
# the version is upstream's RMM version plus the tuned local label
# +shared.cu<n>.<YYYYMMDD>.<seq> (docs/VERSIONING.md), the variant segment being
# "shared" since there is no variant axis. This is safe as long as nothing else
# in the target environment hard-requires upstream's plain librmm/rmm at a
# conflicting version -- see raft_wheel_common.sh's validate_wheels().
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${SOURCE_ARCH:-}" ]]; then
    case "$(uname -m)" in
        aarch64) SOURCE_ARCH=gb10 ;;
        *) echo "ERROR: name the variant whose build supplies rmm: SOURCE_ARCH=rtx40|rtx50 (it has no default on $(uname -m))." >&2; exit 1 ;;
    esac
fi
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "${SOURCE_ARCH}" || exit 1
# shellcheck source=raft_wheel_common.sh
source "${PROJECT_ROOT}/tuned/raft_wheel_common.sh" || exit 1

SOURCE_BUILD_DIR="$(gpu_tuned_out_dir build "${PROJECT_ROOT}" "${CUDA_TAG}" "${SOURCE_ARCH}")"
INSTALL_DIR="${SOURCE_BUILD_DIR}/install"
RMM_SRC="${SOURCE_BUILD_DIR}/_deps/rmm-src"
LIBRMM_SO="librmm-${CUDA_TAG}.so"
LOGGER_SO="librapids_logger-${CUDA_TAG}.so"
[[ -d "${RMM_SRC}" ]] || { echo "ERROR: ${RMM_SRC} not found -- build ${SOURCE_ARCH} first (tuned/build.sh ${SOURCE_ARCH}, CUDA_TAG=${CUDA_TAG})." >&2; exit 1; }
for _so in "${LIBRMM_SO}" "${LOGGER_SO}"; do
    [[ -f "${INSTALL_DIR}/lib/${_so}" ]] || { echo "ERROR: ${INSTALL_DIR}/lib/${_so} not found -- the build predates the toolkit-named libraries; rebuild with tuned/build.sh ${SOURCE_ARCH}." >&2; exit 1; }
    # No device code is the premise of building these once for every variant, and of naming them by toolkit only.
    if gpu_tuned_so_has_device_code "${INSTALL_DIR}/lib/${_so}"; then rc=0; else rc=$?; fi
    [[ ${rc} -eq 1 ]] || { echo "ERROR: ${_so} is not a library without device code (classification rc ${rc}); it cannot be shared across variants." >&2; exit 1; }
done
unset _so rc

RMM_VERSION="$(tr -d '\r' < "${RMM_SRC}/VERSION")"
RMM_SHORT_VER="$(gpu_tuned_short_ver "${RMM_VERSION}")" || exit 1

# The wheel label (docs/ARCHITECTURE.md E1/E4): allocated once, here, and recorded for the release step.
# GPU_TUNED_LABEL_SEQ=0 skips the tag lookup for a build that is never published.
LOCAL_VERSION="$(gpu_tuned_build_local_version shared "${PROJECT_ROOT}")" || exit 1
WHEEL_VERSION="${RMM_VERSION}+${LOCAL_VERSION}"

DIST_DIR="$(gpu_tuned_out_dir dist "${PROJECT_ROOT}" "${CUDA_TAG}" shared)"
WHEEL_SRC_RMM="${SOURCE_BUILD_DIR}/wheel-src-rmm-shared"

echo "librmm/rmm wheels: ${WHEEL_VERSION} (rmm ${RMM_VERSION}, ${CUDA_TAG}, source variant ${SOURCE_ARCH})"
# The build requirements are pip-installed below, so this runs in the toolkit's build venv, never the user's
# environment (C9, tuned-common; it replaces the old check that CONDA_PREFIX was a dedicated venv). CONDA_PREFIX
# points at it because these builds were always run with CONDA_PREFIX=<dedicated venv>.
gpu_tuned_setup_build_venv "${GPU_TUNED_VENV_DIR}" "${PROJECT_ROOT}" || exit 1
export CONDA_PREFIX="${VIRTUAL_ENV}"
echo "Installing build dependencies into ${VIRTUAL_ENV}..."
pip install \
    --extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple \
    -r "${PROJECT_ROOT}/tuned/requirements-build-cuda13x.txt"
# The current setuptools, installed last so nothing above can hold it back (C8, tuned-common).
gpu_tuned_install_setuptools || exit 1

rm -rf "${DIST_DIR}" "${WHEEL_SRC_RMM}"
mkdir -p "${DIST_DIR}" "${WHEEL_SRC_RMM}"
echo "${WHEEL_VERSION}" > "${DIST_DIR}/wheel-version.txt"

stage_dependencies_yaml "${RMM_SRC}" "${WHEEL_SRC_RMM}"
stage_repo_root_refs "${RMM_SRC}" "${WHEEL_SRC_RMM}"

# ── librmm-cuXX (plain name, no variant suffix) ─────────────────────────────
stage_package_source "${RMM_SRC}" "librmm" "${WHEEL_SRC_RMM}"
LIBRMM_STAGED="${WHEEL_SRC_RMM}/python/librmm"

echo "Copying ${LIBRMM_SO} and ${LOGGER_SO} from the build's install tree (no recompile)..."
mkdir -p "${LIBRMM_STAGED}/librmm/lib64"
cp "${INSTALL_DIR}/lib/${LIBRMM_SO}" "${INSTALL_DIR}/lib/${LOGGER_SO}" "${LIBRMM_STAGED}/librmm/lib64/"
gpu_tuned_verify_so_axes "${LIBRMM_STAGED}/librmm/lib64" shared "${CUDA_TAG}" - || exit 1

# Stamp each library with the JSON build info. The variant is "shared": there is no variant axis here.
_nvcc_full="$("${CUDA_HOME}/bin/nvcc" --version | sed -n 's/.*release [0-9.]*, V\([0-9.]*\).*/\1/p' | head -1)"
for _so in "${LIBRMM_SO}" "${LOGGER_SO}"; do
    gpu_tuned_embed_build_info_json "${LIBRMM_STAGED}/librmm/lib64/${_so}" \
        package=librmm "component=${_so}" "release=${WHEEL_VERSION}" variant=shared \
        "hardware=none (no device code; shared by every variant)" \
        "cuda.tag=${CUDA_TAG}" "cuda.version=${CUDA_VER}" "cuda.nvcc=${_nvcc_full:-unknown}" || exit 1
    gpu_tuned_verify_build_info_json "${LIBRMM_STAGED}/librmm/lib64/${_so}" "release=${WHEEL_VERSION}" variant=shared "cuda.tag=${CUDA_TAG}" || exit 1
done
unset _so _nvcc_full

# name/matrix-entry: only matrix-entry needs patching (enables the "-cu13" CUDA suffix rapids_build_backend
# appends) -- name stays the unpatched default "librmm" from source, no variant rename.
patch_line_or_fail "${LIBRMM_STAGED}/pyproject.toml" \
    '^matrix-entry = .*' 'matrix-entry = "cuda_suffixed=true;use_cuda_wheels=true"\ncommit-files = []' \
    "librmm matrix-entry"
echo "${WHEEL_VERSION}" > "${LIBRMM_STAGED}/librmm/VERSION"

# The wheel now ships its own librapids_logger-<toolkit>.so; the stock rapids-logger wheel's librapids_logger.so
# is not what our librmm NEEDs, so drop the runtime dependency. Only the py_cpp_run group (librmm's runtime
# dependencies) changes: the build-time one stays. The group is kept with an EMPTY includes list, because a group with
# no includes key at all is rejected by the dependency-file schema.
python3 - "${WHEEL_SRC_RMM}/dependencies.yaml" <<'PYEOF2'
import re
import sys

path = sys.argv[1]
src = open(path).read()
pattern = re.compile(r"(  py_cpp_run:\n(?:    .*\n)*?    includes:\n)      - depends_on_rapids_logger\n")
if not pattern.search(src):
    sys.exit("ERROR: dependencies.yaml: py_cpp_run does not include only depends_on_rapids_logger; upstream changed.")
src = pattern.sub(lambda m: m.group(1).rstrip("\n").removesuffix("includes:") + "includes: []\n", src, count=1)
open(path, "w").write(src)
PYEOF2
[[ $? -eq 0 ]] || exit 1

# load.py: load OUR bundled logger first (it replaces the import of the stock rapids_logger package), then librmm
# under its toolkit-named file. Both patches fail loudly if upstream's loader changed shape.
python3 - "${LIBRMM_STAGED}/librmm/load.py" "${LIBRMM_SO}" "${LOGGER_SO}" <<'PYEOF'
import re
import sys

path, librmm_so, logger_so = sys.argv[1:4]
src = open(path).read()
pattern = re.compile(
    r"    try:\n        # rapids-logger must be loaded before librmm.*?\n        pass\n", re.S
)
if not pattern.search(src):
    sys.exit("ERROR: librmm load.py: the rapids_logger import block was not found; upstream's loader changed.")
src = pattern.sub(
    "    # The wheel bundles librmm's runtime dependency under its tuned name; it must be loaded before librmm.\n"
    f'    _load_wheel_installation("{logger_so}")\n',
    src,
    count=1,
)
if src.count('soname = "librmm.so"') != 1:
    sys.exit("ERROR: librmm load.py: soname = \"librmm.so\" not found exactly once; upstream's loader changed.")
src = src.replace('soname = "librmm.so"', f'soname = "{librmm_so}"')
open(path, "w").write(src)
PYEOF
[[ $? -eq 0 ]] || exit 1

echo "Building librmm-cu13 wheel ${WHEEL_VERSION} for ${GPU_TUNED_PLATFORM} (bundles ${LIBRMM_SO}, ${LOGGER_SO})..."
SKBUILD_CMAKE_ARGS="-DCMAKE_PREFIX_PATH=${INSTALL_DIR}" \
    pip wheel \
        --no-deps \
        --no-build-isolation \
        --wheel-dir "${DIST_DIR}" \
        "${LIBRMM_STAGED}"

LIBRMM_WHEEL="$(ls "${DIST_DIR}"/librmm*.whl 2>/dev/null | head -1)" || true
[[ -z "${LIBRMM_WHEEL}" ]] && { echo "ERROR: librmm wheel not found" >&2; exit 1; }
echo "librmm wheel: $(basename "${LIBRMM_WHEEL}") ($(du -sh "${LIBRMM_WHEEL}" | awk '{print $1}'))"

# ── rmm-cuXX (plain name, no variant suffix) ────────────────────────────────
# Real compile (Cython extensions), not an extract-a-prebuilt-.so step.
stage_package_source "${RMM_SRC}" "rmm" "${WHEEL_SRC_RMM}"
RMM_STAGED="${WHEEL_SRC_RMM}/python/rmm"

patch_line_or_fail "${RMM_STAGED}/pyproject.toml" \
    '^matrix-entry = .*' 'matrix-entry = "cuda_suffixed=true"\ncommit-files = []' \
    "rmm matrix-entry"
echo "${WHEEL_VERSION}" > "${RMM_STAGED}/rmm/VERSION"
# rmm's own dependencies.yaml already correctly pins librmm==<RMM_SHORT_VER>.* (its own actual version), which the
# local version above satisfies -- no patch needed since we didn't rename librmm's distribution either.

echo "Building rmm-cu13 wheel ${WHEEL_VERSION} for ${GPU_TUNED_PLATFORM}..."
SKBUILD_CMAKE_ARGS="-DCMAKE_PREFIX_PATH=${INSTALL_DIR}" \
    pip wheel \
        --no-deps \
        --no-build-isolation \
        --wheel-dir "${DIST_DIR}" \
        "${RMM_STAGED}"

RMM_WHEEL="$(ls "${DIST_DIR}"/rmm_*.whl 2>/dev/null | head -1)" || true
[[ -z "${RMM_WHEEL}" ]] && { echo "ERROR: rmm wheel not found" >&2; exit 1; }
echo "rmm wheel: $(basename "${RMM_WHEEL}") ($(du -sh "${RMM_WHEEL}" | awk '{print $1}'))"

# Dependency gates (H9, H10; tuned-common): the build venv's setuptools, then each wheel's runtime dependencies. The
# sibling wheel comes from this dist directory and RAPIDS nightly packages from their index (listed as "not audited").
gpu_tuned_check_venv_setuptools "${GPU_TUNED_VENV_DIR}" || exit 1
for w in "${DIST_DIR}"/librmm*.whl "${RMM_WHEEL}"; do
    gpu_tuned_audit_deps "${w}" "${GPU_TUNED_BUILD_ROOT}/dependency-audit-$(basename "${w}" .whl).log" \
        --find-links "${DIST_DIR}" --extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple \
        || { echo "ERROR: dependency audit failed for $(basename "${w}") (see above)." >&2; exit 1; }
done

echo ""
echo "Built (not published): ${DIST_DIR}"
echo "  version ${WHEEL_VERSION}"
echo "Next: validate in a scratch environment, then a separate gated release step."
