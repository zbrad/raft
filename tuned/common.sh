#!/bin/bash
# tuned-common.sh — shared build-tooling functions for the GB10/RTX40/RTX50
# "tuned-builds" fleet (pytorch, llama.cpp, flash-attention, flashinfer,
# raft, cuvs, faiss, and downstream consumers like vllm/ComfyUI/open-webui).
#
# Source this file; it defines functions only (no exports) so it's safe to
# source before or after a repo's own tuned/env.sh sets its device-specific
# vars. The ONE intentional side effect is the loud-failure ERR trap
# installed at the bottom of this file (see "Loud failures" there; opt out
# with GPU_TUNED_NO_ERR_TRAP=1). Every function takes its inputs as explicit
# arguments -- none of them read a repo-specific global var name (that's
# the whole point: this file is meant to be byte-identical across every
# consumer, so it's fetched/vendored, not hand-copied-and-edited).
#
# Consuming repo's own tuned/env.sh is still where device-specific stuff
# lives: reading tuned/devices/<variant>.conf, exporting whatever
# arch/toolkit env vars that repo's build system actually expects
# (TORCH_CUDA_ARCH_LIST, FA2_TUNED_ARCH, FLASHINFER_CUDA_ARCH_LIST, ...),
# and any host-assertion call using the generic functions below.
#
# Repo: https://github.com/zbrad/tuned-common

# gpu_tuned_installed_cuda_toolkits — lists installed /usr/local/cuda-<ver>
# toolkit versions, sorted ascending. Generic replacement for each repo's
# own <prefix>_installed_cuda_toolkits() (pytorch_/flash_attn_/cuvs_/
# faiss_/llama_tuned_ — same body every time, only the name differed).
gpu_tuned_installed_cuda_toolkits() {
    local d
    for d in /usr/local/cuda-[0-9]*; do
        [ -d "$d" ] && basename "$d" | sed 's/^cuda-//'
    done | sort -V
}

# gpu_tuned_resolve_cuda_home — sets CUDA_HOME (to the highest installed
# toolkit) and CUDA_VERSION_COMPACT (e.g. "133" for CUDA 13.3) unless
# CUDA_HOME is already set in the environment, and prepends
# $CUDA_HOME/bin to PATH. No-op (with a warning) if no toolkit is found.
gpu_tuned_resolve_cuda_home() {
    if [ -z "${CUDA_HOME:-}" ]; then
        local highest
        highest="$(gpu_tuned_installed_cuda_toolkits | tail -1)"
        if [ -n "$highest" ]; then
            export CUDA_HOME="/usr/local/cuda-${highest}"
        else
            echo "[tuned-common] WARNING: no /usr/local/cuda-<ver> toolkit found; leaving CUDA_HOME unset." >&2
            echo "[tuned-common]          Set CUDA_HOME explicitly to an installed toolkit." >&2
            return 0
        fi
    fi
    export PATH="${CUDA_HOME}/bin:${PATH}"
    CUDA_VERSION_COMPACT="$(basename "${CUDA_HOME}" | sed -E 's/^cuda-([0-9]+)\.([0-9]+).*/\1\2/')"
    export CUDA_VERSION_COMPACT
}

# gpu_tuned_assert_platform <expected-uname-m> <variant-label> — fail
# loudly if this host's CPU architecture doesn't match, rather than
# letting a mismatched build silently produce a wrong-architecture
# artifact that only surfaces as a confusing failure several steps later.
gpu_tuned_assert_platform() {
    local expected="$1" variant="${2:-<unset>}"
    if [[ "$(uname -m)" != "${expected}" ]]; then
        echo "ERROR: gpu_tuned_assert_platform: expected platform '${expected}' for" \
             "variant '${variant}', but uname -m reports '$(uname -m)'." >&2
        return 1
    fi
}

# gpu_tuned_assert_compute_cap <expected-compute-cap> <hw-label> — fail
# loudly if this host's GPU compute capability (via nvidia-smi) doesn't
# match, rather than silently building for whatever GPU is actually
# present. Alternative to gpu_tuned_assert_platform for repos gated by GPU
# match rather than (or in addition to) CPU architecture.
gpu_tuned_assert_compute_cap() {
    local expected="$1" hw_label="${2:-<unset>}"
    local detected
    detected="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' \r')"
    if [[ "${detected}" != "${expected}" ]]; then
        echo "ERROR: gpu_tuned_assert_compute_cap: detected GPU compute capability '${detected}'," \
             "expected '${expected}' (${hw_label})." >&2
        echo "       This is the tuned-builds branch; use upstream main for other GPUs." >&2
        return 1
    fi
}

# gpu_tuned_verify_arch <path-to-.so> <expected-arch> — confirms a
# compiled library's embedded cubin(s) are EXACTLY sm_<expected-arch>
# (dots stripped automatically, e.g. "12.1a" -> "sm_121a"), via cuobjdump.
# Fails if no cubins are found, if MULTIPLE arch targets are embedded
# (this is supposed to be a single-arch tuned build, not a fat multi-arch
# one), or if the one found doesn't match.
gpu_tuned_verify_arch() {
    local so_file="$1" expected_arch="$2"
    if [[ ! -f "${so_file}" ]]; then
        echo "ERROR: gpu_tuned_verify_arch: no such file: ${so_file}" >&2
        return 1
    fi
    command -v cuobjdump >/dev/null 2>&1 || {
        echo "ERROR: gpu_tuned_verify_arch: cuobjdump not found on PATH (expected under \$CUDA_HOME/bin)." >&2
        return 1
    }
    local expected found found_count
    expected="$(echo "${expected_arch}" | tr -d '.')"
    found="$(cuobjdump --list-elf "${so_file}" 2>/dev/null | grep -oE 'sm_[0-9]+[a-z]?' | sort -u)"
    if [[ -z "${found}" ]]; then
        echo "ERROR: gpu_tuned_verify_arch: cuobjdump found no embedded cubins in ${so_file} at all." >&2
        return 1
    fi
    found_count="$(echo "${found}" | wc -l)"
    if [[ "${found_count}" -ne 1 ]]; then
        echo "ERROR: ${so_file} embeds MULTIPLE arch targets ($(echo "${found}" | tr '\n' ' ')) -- this is supposed to be a single-arch tuned build, not a fat multi-arch one." >&2
        return 1
    fi
    if [[ "${found}" != "sm_${expected}" ]]; then
        echo "ERROR: ${so_file} is not built for sm_${expected} (found: ${found})." >&2
        return 1
    fi
    echo "OK: ${so_file} confirmed single-arch ${found} (matches requested sm_${expected})"
}

# gpu_tuned_verify_cuda_compat <path-to-.so> <expected-cuda-ver> —
# confirms the NEEDED libcudart.so.<major> matches the CUDA major version
# this build expects. CUDA's runtime ABI is only forward-compatible within
# the same major version, so a minor-version mismatch is fine but a major
# mismatch is a real problem.
gpu_tuned_verify_cuda_compat() {
    local so_file="$1" expected_cuda_ver="$2"
    if [[ ! -f "${so_file}" ]]; then
        echo "ERROR: gpu_tuned_verify_cuda_compat: no such file: ${so_file}" >&2
        return 1
    fi
    command -v objdump >/dev/null 2>&1 || {
        echo "ERROR: gpu_tuned_verify_cuda_compat: objdump not found on PATH." >&2
        return 1
    }
    local needed found_major expected_major
    needed="$(objdump -p "${so_file}" 2>/dev/null | grep -oE 'libcudart\.so\.[0-9]+' | head -1)"
    if [[ -z "${needed}" ]]; then
        echo "WARNING: ${so_file} has no direct libcudart.so.N NEEDED entry -- skipping CUDA runtime compat check." >&2
        return 0
    fi
    found_major="${needed##*.}"
    expected_major="${expected_cuda_ver%%.*}"
    if [[ "${found_major}" != "${expected_major}" ]]; then
        echo "ERROR: ${so_file} was linked against CUDA runtime major ${found_major}" \
             "(${needed}), but this build expects CUDA ${expected_cuda_ver}" \
             "(major ${expected_major}). CUDA's runtime ABI is only forward-compatible" \
             "within the same major version." >&2
        return 1
    fi
    echo "OK: ${so_file} CUDA runtime compat confirmed (${needed}, matches expected major ${expected_major})"
}

# gpu_tuned_verify_cccl_version <cccl-src-dir> <min-version> — confirms the
# CCCL version CPM fetched into <cccl-src-dir> (read from its
# cccl-version.json, e.g. {"major":3,"minor":5,"patch":0}) is >=
# <min-version> ("major.minor.patch"). Warns (does not fail) rather than
# erroring if cccl-version.json isn't found, since not every CCCL-consuming
# repo necessarily vendors it via CPM the same way -- this is a targeted
# regression guard, not a hard CCCL dependency check.
#
# Why this exists: raft hit a real memory-corruption bug on Blackwell/
# SM_12x (thrust::exclusive_scan silently writing OOB when its input and
# output iterators have mismatched types) that turned out to already be
# fixed upstream in CCCL -- backported to branch/3.4.x and first released
# in CCCL v3.4.0. A raft-side fix was opened (NVIDIA/raft#3141) then
# closed once that was verified empirically (reverted the fix, reran
# clean under compute-sanitizer + the full regression suite against
# current CCCL). Without this check, silently pinning an older CCCL
# (e.g. rolling back a rapids-cmake pin) would reintroduce that exact bug
# with no build-time signal.
gpu_tuned_verify_cccl_version() {
    local cccl_src_dir="$1" min_version="$2"
    local version_file="${cccl_src_dir}/cccl-version.json"
    if [[ ! -f "${version_file}" ]]; then
        echo "WARNING: gpu_tuned_verify_cccl_version: no cccl-version.json found at ${version_file} -- skipping CCCL version check." >&2
        return 0
    fi
    local found_major found_minor found_patch
    found_major="$(grep -oE '"major"[[:space:]]*:[[:space:]]*[0-9]+' "${version_file}" | grep -oE '[0-9]+$')"
    found_minor="$(grep -oE '"minor"[[:space:]]*:[[:space:]]*[0-9]+' "${version_file}" | grep -oE '[0-9]+$')"
    found_patch="$(grep -oE '"patch"[[:space:]]*:[[:space:]]*[0-9]+' "${version_file}" | grep -oE '[0-9]+$')"
    if [[ -z "${found_major}" || -z "${found_minor}" || -z "${found_patch}" ]]; then
        echo "WARNING: gpu_tuned_verify_cccl_version: could not parse major/minor/patch from ${version_file} -- skipping CCCL version check." >&2
        return 0
    fi
    local min_major min_minor min_patch
    IFS='.' read -r min_major min_minor min_patch <<< "${min_version}"
    local found_tuple min_tuple
    found_tuple="$(printf '%05d%05d%05d' "${found_major}" "${found_minor}" "${found_patch}")"
    min_tuple="$(printf '%05d%05d%05d' "${min_major:-0}" "${min_minor:-0}" "${min_patch:-0}")"
    if [[ "${found_tuple}" < "${min_tuple}" ]]; then
        echo "ERROR: CCCL ${found_major}.${found_minor}.${found_patch} (from ${version_file}) is older than the required minimum ${min_version}." >&2
        echo "       CCCL < 3.4.0 lacks the warpspeed-scan fixes (NVIDIA/cccl#9207, #9781) needed to avoid a real" >&2
        echo "       memory-corruption bug on Blackwell/SM_12x (thrust::exclusive_scan with mismatched" >&2
        echo "       input/output types) -- see NVIDIA/raft#3141 (closed, not needed) for the empirical verification" >&2
        echo "       this minimum is based on." >&2
        return 1
    fi
    echo "OK: CCCL ${found_major}.${found_minor}.${found_patch} meets the minimum required version (${min_version})"
}

# gpu_tuned_load_toolkit <data-dir> <variant> [<toolkit-id>] — selects a CUDA
# toolkit from <data-dir>/toolkits/<toolkit-id>.env (e.g. cu133), then
# sources the optional <data-dir>/toolkits/<variant>-<toolkit-id>.env, which
# overrides any key. With no id it uses the highest defined toolkit (by its
# declared TOOLKIT_CUDA_VER, not by file name) and says so on stderr, naming
# the whole list and the reason. It only ever picks from the toolkit files,
# never from /usr/local/cuda or from what happens to be installed. An unknown
# id is an error that lists the available ones, and an already-set CUDA_HOME
# that differs from the toolkit's is rejected rather than trusted. Exports
# CUDA_VER, CUDA_TAG, CUDA_HOME, GPU_TUNED_TOOLKIT_LIB_DIR (the toolkit's own
# targets/<arch>-linux/lib, from GPU_TUNED_PLATFORM when set, else uname -m)
# and prepends $CUDA_HOME/bin to PATH. It does not check the install: call
# gpu_tuned_verify_toolkit for that.
gpu_tuned_load_toolkit() {
    local data_dir="$1" variant="$2" tk="${3:-}"
    if [[ -z "${tk}" ]]; then
        local f v listing="" best="" best_v=""
        for f in "${data_dir}"/toolkits/*.env; do
            [[ -f "${f}" ]] || continue
            [[ "$(basename "${f}" .env)" == "${variant}-"* ]] && continue   # per-variant override file
            v="$(sed -n 's/^TOOLKIT_CUDA_VER="\(.*\)"$/\1/p' "${f}" | head -1)"
            listing+=" $(basename "${f}" .env)(${v:-?})"
            if [[ -n "${v}" && ( -z "${best_v}" || "$(printf '%s\n%s\n' "${best_v}" "${v}" | sort -V | tail -1)" == "${v}" ) ]]; then
                best="$(basename "${f}" .env)"; best_v="${v}"
            fi
        done
        if [[ -z "${best}" ]]; then
            echo "ERROR: gpu_tuned_load_toolkit: no toolkit given and none defined under ${data_dir}/toolkits" >&2
            return 1
        fi
        echo "[toolkit] available:${listing}" >&2
        local dflt=""
        if [[ -f "${data_dir}/toolkits/DEFAULT" ]]; then
            dflt="$(tr -d '[:space:]' < "${data_dir}/toolkits/DEFAULT")"
            if [[ ! -f "${data_dir}/toolkits/${dflt}.env" ]]; then
                echo "ERROR: gpu_tuned_load_toolkit: ${data_dir}/toolkits/DEFAULT names '${dflt}', which has no toolkits/${dflt}.env." >&2
                return 1
            fi
            echo "[toolkit] using ${dflt}: none was specified, so the default named in toolkits/DEFAULT is used (highest defined is ${best})." >&2
            echo "[toolkit] to choose another, set CUDA_TAG (e.g. CUDA_TAG=${best}) or CUDA_VER." >&2
            tk="${dflt}"
        else
            echo "[toolkit] using ${best} (CUDA ${best_v}): none was specified, so the highest defined toolkit is used." >&2
            echo "[toolkit] to choose another, set CUDA_TAG (e.g. CUDA_TAG=${best}) or CUDA_VER." >&2
            tk="${best}"
        fi
    fi
    local base="${data_dir}/toolkits/${tk}.env"
    local over="${data_dir}/toolkits/${variant}-${tk}.env"
    if [[ ! -f "${base}" ]]; then
        local f avail=""
        for f in "${data_dir}"/toolkits/*.env; do
            [[ -f "${f}" ]] && avail+=" $(basename "${f}" .env)"
        done
        echo "ERROR: gpu_tuned_load_toolkit: no toolkit file ${base}" >&2
        echo "       available toolkits:${avail:- (none)}" >&2
        return 1
    fi
    unset TOOLKIT_ID TOOLKIT_CUDA_VER TOOLKIT_CUDA_HOME TOOLKIT_NVCC_RELEASE TOOLKIT_NCCL_VERSION
    # shellcheck disable=SC1090
    source "${base}"
    # shellcheck disable=SC1090
    [[ -f "${over}" ]] && source "${over}"
    local k
    for k in TOOLKIT_ID TOOLKIT_CUDA_VER TOOLKIT_CUDA_HOME TOOLKIT_NVCC_RELEASE; do
        if [[ -z "${!k:-}" ]]; then
            echo "ERROR: gpu_tuned_load_toolkit: ${base} does not set ${k}" >&2
            return 1
        fi
    done
    if [[ "${TOOLKIT_ID}" != "${tk}" ]]; then
        echo "ERROR: gpu_tuned_load_toolkit: ${base} sets TOOLKIT_ID=${TOOLKIT_ID}, expected ${tk}" >&2
        return 1
    fi
    if [[ -n "${CUDA_HOME:-}" && "${CUDA_HOME}" != "${TOOLKIT_CUDA_HOME}" ]]; then
        echo "ERROR: gpu_tuned_load_toolkit: CUDA_HOME is '${CUDA_HOME}' but toolkit ${tk} requires ${TOOLKIT_CUDA_HOME}." >&2
        echo "       Unset CUDA_HOME or point it at the toolkit-versioned directory." >&2
        return 1
    fi
    local platform="${GPU_TUNED_PLATFORM:-$(uname -m)}" target
    case "${platform}" in
        aarch64) target="sbsa-linux" ;;
        x86_64) target="x86_64-linux" ;;
        *) echo "ERROR: gpu_tuned_load_toolkit: unsupported platform '${platform}'" >&2; return 1 ;;
    esac
    export CUDA_VER="${TOOLKIT_CUDA_VER}"
    export CUDA_TAG="${tk}"
    export CUDA_HOME="${TOOLKIT_CUDA_HOME}"
    export GPU_TUNED_TOOLKIT_LIB_DIR="${CUDA_HOME}/targets/${target}/lib"
    export PATH="${CUDA_HOME}/bin:${PATH}"
}

# gpu_tuned_verify_toolkit — after gpu_tuned_load_toolkit, confirms the
# install matches its definition: nvcc exists under CUDA_HOME and reports the
# declared "release X.Y", and (when TOOLKIT_NCCL_VERSION is set) the installed
# libnccl2 package is exactly that version. A mismatched NCCL is the quiet
# failure: apt holds one libnccl2 at a time, so a toolkit other than the one
# it was built for would be bundled with a foreign NCCL.
gpu_tuned_verify_toolkit() {
    if [[ -z "${TOOLKIT_ID:-}" ]]; then
        echo "ERROR: gpu_tuned_verify_toolkit: no toolkit loaded (call gpu_tuned_load_toolkit first)." >&2
        return 1
    fi
    if [[ "${CUDA_HOME:-}" != "${TOOLKIT_CUDA_HOME}" ]]; then
        echo "ERROR: gpu_tuned_verify_toolkit: CUDA_HOME is '${CUDA_HOME:-}', expected ${TOOLKIT_CUDA_HOME}." >&2
        return 1
    fi
    if [[ ! -x "${CUDA_HOME}/bin/nvcc" ]]; then
        echo "ERROR: gpu_tuned_verify_toolkit: ${CUDA_HOME}/bin/nvcc not found; toolkit ${TOOLKIT_ID} is not installed." >&2
        return 1
    fi
    local found
    found="$("${CUDA_HOME}/bin/nvcc" --version 2>/dev/null | grep -oE 'release [0-9]+\.[0-9]+' | head -1 | awk '{print $2}' || true)"
    if [[ "${found}" != "${TOOLKIT_NVCC_RELEASE}" ]]; then
        echo "ERROR: gpu_tuned_verify_toolkit: ${CUDA_HOME}/bin/nvcc reports release '${found}', toolkit ${TOOLKIT_ID} declares ${TOOLKIT_NVCC_RELEASE}." >&2
        return 1
    fi
    if [[ -n "${TOOLKIT_NCCL_VERSION:-}" ]]; then
        if ! command -v dpkg-query >/dev/null 2>&1; then
            echo "WARNING: gpu_tuned_verify_toolkit: dpkg-query not found; NCCL ${TOOLKIT_NCCL_VERSION} not checked." >&2
        else
            local nccl
            nccl="$(dpkg-query -W -f='${Version}' libnccl2 2>/dev/null || true)"
            if [[ "${nccl}" != "${TOOLKIT_NCCL_VERSION}" ]]; then
                echo "ERROR: gpu_tuned_verify_toolkit: libnccl2 is '${nccl:-not installed}', toolkit ${TOOLKIT_ID} declares ${TOOLKIT_NCCL_VERSION}." >&2
                return 1
            fi
        fi
    fi
    echo "OK: toolkit ${TOOLKIT_ID}: nvcc ${found} at ${CUDA_HOME}${TOOLKIT_NCCL_VERSION:+, libnccl2 ${TOOLKIT_NCCL_VERSION}}"
}

# gpu_tuned_verify_toolkit_libs <elf>... — resolves each file's libraries
# with ldd under LD_LIBRARY_PATH=$GPU_TUNED_TOOLKIT_LIB_DIR and requires that
# libcudart/libcublas/libcublasLt come from under CUDA_HOME and that no
# library comes from a different /usr/local/cuda* tree. Without this, the
# loader's ld.so.conf entries (which follow the /usr/local/cuda symlink to the
# newest toolkit) can satisfy the lookup from the wrong version and a
# "does it load" test passes against the wrong runtime.
gpu_tuned_verify_toolkit_libs() {
    if [[ -z "${GPU_TUNED_TOOLKIT_LIB_DIR:-}" ]]; then
        echo "ERROR: gpu_tuned_verify_toolkit_libs: no toolkit loaded (call gpu_tuned_load_toolkit first)." >&2
        return 1
    fi
    local f line name path real rc=0
    for f in "$@"; do
        while IFS= read -r line; do
            # ldd lines are "<tab>name => path (addr)"; awk also trims the tab.
            name="$(awk '{ print $1 }' <<< "${line}")"
            path="$(awk '{ for (i = 1; i <= NF; i++) if ($i == "=>") { print $(i + 1); exit } }' <<< "${line}")"
            [[ "${path}" == /* ]] || continue
            real="$(readlink -f "${path}")"
            if [[ "${name}" =~ ^lib(cudart|cublas|cublasLt)\.so ]] && [[ "${real}" != "${CUDA_HOME}"/* ]]; then
                echo "ERROR: $(basename "${f}"): ${name} resolves to ${real}, not under ${CUDA_HOME}." >&2
                rc=1
            elif [[ "${real}" == /usr/local/cuda* && "${real}" != "${CUDA_HOME}"/* ]]; then
                echo "ERROR: $(basename "${f}"): ${name} resolves to ${real}, a different CUDA tree than ${CUDA_HOME}." >&2
                rc=1
            fi
        done < <(LD_LIBRARY_PATH="${GPU_TUNED_TOOLKIT_LIB_DIR}" ldd "${f}" 2>/dev/null || true)
    done
    return "${rc}"
}

# gpu_tuned_load_repo_env <file> — sources a repo's tuned/repo.env, which holds
# only what is specific to that repo (CMake flags, paths, extra packages) and
# must never change what the shared device and toolkit files decided. After
# sourcing, every protected key (hardware, toolkit, CUDA_*) is compared with
# its value from before; ALL changed, newly set or unset keys are reported in
# one loud block and the function fails, so a repo cannot quietly drift from
# the shared definitions. Call it after gpu_tuned_load_toolkit.
GPU_TUNED_PROTECTED_KEYS=(
    GPU_TUNED_VARIANT GPU_TUNED_PLATFORM GPU_TUNED_CUDA_ARCH GPU_TUNED_HW_LABEL
    GPU_TUNED_TOOLKIT_LIB_DIR CUDA_VER CUDA_TAG CUDA_HOME
    TOOLKIT_ID TOOLKIT_CUDA_VER TOOLKIT_CUDA_HOME TOOLKIT_NVCC_RELEASE TOOLKIT_NCCL_VERSION
)
gpu_tuned_load_repo_env() {
    local file="$1"
    if [[ ! -f "${file}" ]]; then
        echo "ERROR: gpu_tuned_load_repo_env: no such file: ${file}" >&2
        return 1
    fi
    local k
    local -A was_set=() was_val=()
    for k in "${GPU_TUNED_PROTECTED_KEYS[@]}"; do
        if [[ -n "${!k+x}" ]]; then was_set[${k}]=1; was_val[${k}]="${!k}"; else was_set[${k}]=0; fi
    done
    # shellcheck disable=SC1090
    source "${file}"
    local conflicts=""
    for k in "${GPU_TUNED_PROTECTED_KEYS[@]}"; do
        if [[ -n "${!k+x}" ]]; then
            if [[ "${was_set[${k}]}" -eq 0 ]]; then
                conflicts+="    ${k}: was unset, ${file##*/} sets it to '${!k}'"$'\n'
            elif [[ "${!k}" != "${was_val[${k}]}" ]]; then
                conflicts+="    ${k}: '${was_val[${k}]}' -> '${!k}'"$'\n'
            fi
        elif [[ "${was_set[${k}]}" -eq 1 ]]; then
            conflicts+="    ${k}: '${was_val[${k}]}' -> (unset)"$'\n'
        fi
    done
    if [[ -n "${conflicts}" ]]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
        echo "ERROR: ${file} conflicts with the shared device/toolkit definitions:" >&2
        printf '%s' "${conflicts}" >&2
        echo "  repo.env may only add repo-specific settings. Remove these lines, or" >&2
        echo "  change the shared file in zbrad/tuned-common if the shared value is wrong." >&2
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
        return 1
    fi
}

# gpu_tuned_public_repo_url <remote-url> — the public https form of a git
# remote, safe to stamp into a published binary: scp-style and ssh:// remotes
# become https://<host>/<path>, any userinfo (including an `org-123@` SSH host
# alias or an embedded token) is dropped, and a trailing .git is removed.
gpu_tuned_public_repo_url() {
    printf '%s' "${1:-}" | sed -E \
        's#\.git$##; s#^ssh://[^@/]*@([^/:]+)(:[0-9]+)?/#https://\1/#; s#^[^@/:]+@([^:/]+):#https://\1/#; s#^(https?://)[^/@]*@#\1#'
}

# gpu_tuned_git_provenance [fork-url] — one line naming the exact fork and
# upstream commits the current checkout was built from, for the build-info
# stamp. Run from inside the repo (like the stamp itself). Always returns 0 and
# never prints to stderr: every git call is guarded, so a non-fork, a shallow
# or temp-dir wheel build, or a missing upstream ref yields an explicit marker
# instead of tripping the ERR trap.
#
#   fork <url> sha <40-hex>[ dirty][ tag <tuning-tag>], upstream <url> ref <ref> base <40-hex> nearest <tag>+<N>
#
#  - fork sha is the full HEAD hash; " dirty" is added if tracked files differ
#    from HEAD (the stamp would otherwise misidentify the build).
#  - fork tag is GPU_TUNED_BUILD_INFO_TAG if the caller supplies it, else a
#    tuning-* tag already pointing at HEAD. A release script usually tags only
#    after the build, so the caller (or the release-tag helper) must pass it.
#  - upstream ref is GPU_TUNED_UPSTREAM_REF (declare it per repo, e.g. in
#    tuned/repo.env: upstream/master) or, failing that, upstream/HEAD if git
#    has one. It is NOT guessed from main/master/develop: several upstreams
#    release from a branch that main does not contain.
#  - upstream base is merge-base(HEAD, ref): the upstream commit our tuned work
#    sits on. nearest is the closest upstream tag at or before it and the
#    distance from it; our own tuning-* tags are excluded.
#  - Never fetches. upstream/* is as fresh as the last fetch; build-time
#    freshness is gpu_tuned_check_main_current's job, not the stamp's.
#  - Non-forks stamp "upstream none"; an undeclared ref stamps
#    "ref undeclared"; an unresolvable one "base unknown".
gpu_tuned_git_provenance() {
    local fork_url="${1:-}" sha dirty="" tag up_url up_ref base nearest dist
    if ! sha="$(git rev-parse HEAD 2>/dev/null)"; then
        printf 'fork sha unknown, upstream unknown'
        return 0
    fi
    if [ -z "${fork_url}" ]; then
        fork_url="$(git remote get-url origin 2>/dev/null || true)"
    fi
    fork_url="$(gpu_tuned_public_repo_url "${fork_url}")"
    if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null || true)" ]; then
        dirty=" dirty"
    fi
    tag="${GPU_TUNED_BUILD_INFO_TAG:-}"
    if [ -z "${tag}" ]; then
        tag="$(git describe --exact-match --tags --match 'tuning-*' HEAD 2>/dev/null || true)"
    fi
    printf 'fork %s sha %s%s' "${fork_url:-unknown}" "${sha}" "${dirty}"
    [ -z "${tag}" ] || printf ' tag %s' "${tag}"

    if ! up_url="$(git remote get-url upstream 2>/dev/null)"; then
        printf ', upstream none'
        return 0
    fi
    up_url="$(gpu_tuned_public_repo_url "${up_url}")"
    up_ref="${GPU_TUNED_UPSTREAM_REF:-}"
    if [ -z "${up_ref}" ]; then
        up_ref="$(git symbolic-ref -q --short refs/remotes/upstream/HEAD 2>/dev/null || true)"
    fi
    if [ -z "${up_ref}" ]; then
        printf ', upstream %s ref undeclared' "${up_url}"
        return 0
    fi
    if ! base="$(git merge-base HEAD "${up_ref}" 2>/dev/null)"; then
        printf ', upstream %s ref %s base unknown' "${up_url}" "${up_ref}"
        return 0
    fi
    nearest="$(git describe --tags --abbrev=0 --exclude 'tuning-*' "${base}" 2>/dev/null || true)"
    if [ -n "${nearest}" ]; then
        dist="$(git rev-list --count "refs/tags/${nearest}..${base}" 2>/dev/null || true)"
        nearest="${nearest}+${dist:-?}"
    else
        nearest="none"
    fi
    printf ', upstream %s ref %s base %s nearest %s' "${up_url}" "${up_ref}" "${base}" "${nearest}"
}

# gpu_tuned_embed_build_info <so-or-bin-path> <variant> <package> <version>
# [hw-label] [repo-url] [section-name] — embeds a greppable build-info
# string into a custom ELF section on the given file, readable later via
# `readelf -p <section> <file>` or plain `strings`. Safe at runtime: a
# custom section with no program-header entry is simply ignored by the
# dynamic loader. Idempotent: strips any prior stamp of the same section
# name first (re-running --add-section on an existing section name
# empirically corrupts objcopy's own in-place rewrite).
#
# Section defaults to .<package>_build_info (non-alnum chars in <package>
# replaced with '_') -- pass [section-name] explicitly (with or without
# the leading '.') to override, e.g. when several different packages
# must all land in the SAME fixed section for a downstream consumer that
# greps one constant name (see zbrad/raft's raft_wheel_common.sh, which
# stamps both libraft and librmm into .raft_build_info regardless of
# which package is being stamped).
#
# Always stamps the exact source commit (git rev-parse --short HEAD, run
# from the caller's cwd -- every tuned/build.sh|wheel.sh invokes this from
# REPO_ROOT) in addition to <version>, rather than trusting <version> to
# carry it. It didn't always: some tuned-builds version schemes embed a
# git sha in the version string itself (e.g. pytorch's old
# BASE.dev<date>+git<sha>...), others (e.g. a plain semver, or a
# tuning.<N> commit-count scheme) don't -- a caller passing one of the
# latter used to leave the stamped binary itself with no way back to the
# exact commit, unlike its GitHub release title. Auto-detecting here
# means it can't be forgotten by a caller either way.
#
# Optional GPU_TUNED_BUILD_INFO_DEPS (env var, single line): what this
# artifact bundles or was built against, appended as ", deps <text>" so it
# is readable from the binary itself (e.g. "kvikio 26.12.00, raft
# v26.12-gb10-cu134-g9d97792e"). Unset, the stamp is unchanged. An env var
# rather than an 8th argument so the per-repo embed_build_info wrappers need
# no change.
#
# The stamp also records the fork and upstream commits (see
# gpu_tuned_git_provenance), placed before ", commit <short>" so anything
# already parsing that field is unaffected. Env inputs, all optional:
# GPU_TUNED_UPSTREAM_REF (the upstream ref to base on) and
# GPU_TUNED_BUILD_INFO_TAG (the tuning tag this build will be released as).
gpu_tuned_embed_build_info() {
    local target="$1" variant="$2" package="$3" version="$4" hw_label="${5:-${2}}" repo_url="${6:-}" section_override="${7:-}"
    local section tmp git_sha provenance
    if [ -n "${section_override}" ]; then
        section="${section_override}"
        [[ "${section}" == .* ]] || section=".${section}"
    else
        section=".$(printf '%s' "${package}" | tr -c 'A-Za-z0-9' '_')_build_info"
    fi
    git_sha="$(git rev-parse --short HEAD 2>/dev/null)" || git_sha="unknown"
    provenance="$(gpu_tuned_git_provenance "${repo_url}")"
    tmp="$(mktemp)"
    {
        printf '%s-%s build: %s v%s (%s)' "${package}" "${variant}" "${package}" "${version}" "${hw_label}"
        [ -n "${repo_url}" ] && printf ', %s' "${repo_url}"
        printf ', %s' "${provenance}"
        printf ', commit %s' "${git_sha}"
        [ -n "${GPU_TUNED_BUILD_INFO_DEPS:-}" ] && printf ', deps %s' "${GPU_TUNED_BUILD_INFO_DEPS//$'\n'/ }"
        printf ', built %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "${tmp}"
    objcopy --remove-section "${section}" "${target}" 2>/dev/null || true
    objcopy --add-section "${section}=${tmp}" "${target}"
    rm -f "${tmp}"
}

# gpu_tuned_verify_build_info <file> <package> <expected-version>
# [section-override] — reads back the ELF section gpu_tuned_embed_build_info
# stamped and confirms it exists and actually carries <expected-version>.
# Exists because a stamp can be silently discarded downstream of where it
# was applied: a packaging step (e.g. scikit-build-core's `python -m build
# --wheel`) can run its own fresh install pass into a temp prefix sourced
# from the build tree's own compiled output, never touching -- and
# therefore never carrying forward -- whatever copy was stamped earlier.
# Confirmed empirically for pytorch's wheel.sh: a test marker stamped on
# the pre-build .so did not survive into the built wheel at all. Call this
# on the FINAL shipped artifact (the built wheel's own contents, or the
# installed file in a consuming venv), not just right after stamping a
# pre-build copy -- checking only the latter would have reported success
# in the exact case that was actually broken.
#
# <expected-version> is a substring match (the section's full message
# includes package/variant/hw_label/commit/timestamp around it), so pass
# just the version string, not the whole expected message. Commit sha is
# deliberately not checked: a consumer generally knows the version it
# asked for but not independently which commit that version maps to --
# report the section's full content instead of gating on it.
#
# Hard-fails (non-zero, message to stderr) if the section is missing
# entirely or present but doesn't mention <expected-version>; prints the
# section's content and returns 0 on success.
gpu_tuned_verify_build_info() {
    local file="$1" package="$2" expected_version="$3" section_override="${4:-}"
    local section
    if [ -n "${section_override}" ]; then
        section="${section_override}"
        [[ "${section}" == .* ]] || section=".${section}"
    else
        section=".$(printf '%s' "${package}" | tr -c 'A-Za-z0-9' '_')_build_info"
    fi
    local tmp content
    tmp="$(mktemp)"
    if ! objcopy --dump-section "${section}=${tmp}" "${file}" 2>/dev/null; then
        rm -f "${tmp}"
        echo "ERROR: gpu_tuned_verify_build_info: ${file} has no ${section} section -- the build-info stamp did not survive into this artifact (a packaging/install step likely rebuilt or copied from an unstamped source)." >&2
        return 1
    fi
    content="$(cat "${tmp}")"
    rm -f "${tmp}"
    if [[ -z "${content}" ]]; then
        echo "ERROR: gpu_tuned_verify_build_info: ${file}'s ${section} section is empty." >&2
        return 1
    fi
    if [[ "${content}" != *"${expected_version}"* ]]; then
        echo "ERROR: gpu_tuned_verify_build_info: ${file}'s ${section} section ('${content}') does not mention expected version '${expected_version}' -- wrong/stale binary shipped." >&2
        return 1
    fi
    echo "OK: ${file}'s ${section} section: ${content}"
}

# gpu_tuned_protect_torch_pin <venv-dir> [<exact-torch-version>] — guards a
# venv's tuned (non-PyPI) torch install against being silently swapped out
# by a companion package's exact torch pin (e.g. `pip install torchvision`
# hard-pins torch==2.13.0 and, without this, pip's resolver just
# uninstalls whatever tuned build is there and installs that instead --
# no warning). <exact-torch-version> is read directly from the venv
# itself (`<venv-dir>/bin/python -c 'import torch; print(torch.__version__)'`)
# when omitted; pass it explicitly only to override.
#
# Deriving the version from the venv, rather than requiring the caller to
# type or copy it in, is deliberate: a hand-typed/copy-pasted version
# string from a DIFFERENT repo or session is exactly how zbrad/ComfyUI's
# constraints-gb10.txt ended up pinning a torch build
# (2.15.0+gb10.cu133.tuning.v29) that was never actually installed there
# -- the real install stayed at
# 2.14.0.dev20260707+gitc36325c5ba.gb10.cu133, so the guard was silently
# protecting the wrong version (confirmed 2026-09-22; see that repo's
# tuned_torch_venv_pip_constraint.md).
#
# The GPU codename (variant) is likewise extracted from the version
# string itself -- the first "<variant>.cu<digits>" match (e.g. "gb10" in
# "0.7.0+gb10.cu134.tuning.35", or in the legacy dev form
# "2.14.0.dev20260707+gitc36325c5ba.gb10.cu133") -- and used to name the
# constraints file (constraints-<variant>.txt) instead of the old
# hardcoded "constraints-gb10.txt", which was wrong for any rtx40/rtx50
# venv this ran against. Fails loudly, rather than defaulting to "gb10",
# if no variant marker is found.
#
# Writes <venv-dir>/../constraints-<variant>.txt (one line: the pinned
# torch version) and <venv-dir>/pip.conf (constraint= pointing at it) --
# pip reads {sys.prefix}/pip.conf automatically for any venv-prefixed
# `pip`/`python -m pip` invocation, no activation needed. Idempotent:
# safe to call again after rebuilding/reinstalling the tuned torch wheel.
#
# Effect once wired in: a future `pip install torchvision` (or anything
# else that hard-pins torch) fails loudly with a ResolutionImpossible
# conflict instead of silently downgrading torch. When that happens and
# the package is actually needed: `pip install --no-deps <package>`, then
# manually verify it still works against the tuned torch (a real call on
# a CUDA tensor, not just import -- see zbrad/ComfyUI project memory
# for the torchvision/torchaudio compatibility checks done this way).
gpu_tuned_protect_torch_pin() {
    local venv_dir="$1" torch_version="${2:-}"
    if [[ -z "${venv_dir}" ]]; then
        echo "ERROR: gpu_tuned_protect_torch_pin: usage: gpu_tuned_protect_torch_pin <venv-dir> [<exact-torch-version>]" >&2
        return 1
    fi
    if [[ ! -d "${venv_dir}" ]]; then
        echo "ERROR: gpu_tuned_protect_torch_pin: no such venv dir: ${venv_dir}" >&2
        return 1
    fi
    if [[ -z "${torch_version}" ]]; then
        local py="${venv_dir}/bin/python"
        if [[ ! -x "${py}" ]]; then
            echo "ERROR: gpu_tuned_protect_torch_pin: no python at ${py}" >&2
            return 1
        fi
        torch_version="$("${py}" -c 'import torch; print(torch.__version__)' 2>/dev/null)" || true
        if [[ -z "${torch_version}" ]]; then
            echo "ERROR: gpu_tuned_protect_torch_pin: '${py} -c \"import torch\"' produced no version -- is torch installed in ${venv_dir}?" >&2
            return 1
        fi
    fi

    local variant
    variant="$(grep -oE '[a-z][a-z0-9]*\.cu[0-9]+' <<< "${torch_version}" | head -1 | sed -E 's/\.cu[0-9]+$//')" || true
    if [[ -z "${variant}" ]]; then
        echo "ERROR: gpu_tuned_protect_torch_pin: no '<variant>.cu<digits>' marker found in '${torch_version}' -- not a tuned build?" >&2
        return 1
    fi

    local repo_dir constraints_file
    repo_dir="$(cd "${venv_dir}/.." && pwd)"
    constraints_file="${repo_dir}/constraints-${variant}.txt"

    cat > "${constraints_file}" <<EOF
# Pins the ${variant}-tuned torch build so any future \`pip install\` in
# this venv is forced to keep it -- without this, pip's resolver treats
# an exact torch pin from a dependency (e.g. torchvision/torchaudio
# hard-pinning a specific torch version) as authoritative and silently
# uninstalls the tuned build in favor of a generic PyPI one. Wired in via
# <venv>/pip.conf's [install] constraint=. Generated by
# gpu_tuned_protect_torch_pin (zbrad/tuned-common), which reads this
# version directly from the venv's own \`torch.__version__\` -- rerun it
# whenever the tuned torch wheel is rebuilt/reinstalled to refresh this
# pin, rather than hand-editing the version string below.
torch==${torch_version}
EOF

    cat > "${venv_dir}/pip.conf" <<EOF
[install]
constraint = ${constraints_file}
EOF

    echo "OK: pinned torch==${torch_version} for ${venv_dir} (constraint: ${constraints_file})"
}

# gpu_tuned_short_ver <version-string> — reduces a "x.y.z..." version (any
# number of trailing dot-separated components -- patch, build metadata,
# etc.) to "x.y", stripping leading zeros from x/y (e.g. "26.10.00" ->
# "26.10", "01.02.3" -> "1.2"). Errors rather than silently echoing the
# unmodified input if <version-string> doesn't have at least an "x.y."
# prefix to reduce. Consolidates a regex independently duplicated 5 times
# across raft's and faiss's own package.sh/release.sh/wheel.sh.
gpu_tuned_short_ver() {
    local version="$1" short
    short="$(printf '%s' "${version}" | sed -E 's/^0*([0-9]+)\.0*([0-9]+)\..*/\1.\2/')"
    if [[ ! "${short}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: gpu_tuned_short_ver: could not reduce '${version}' to an 'x.y' short version (expected at least 'x.y.<something>')." >&2
        return 1
    fi
    echo "${short}"
}

# gpu_tuned_cuda_subdir <base-dir> <cuda-tag> [<variant>] — prints
# <base-dir>/<cuda-tag>[/<variant>], the CUDA-version-specific form of a
# per-repo output directory, so builds against two CUDA toolkits never share
# one (a shared build dir carries the other toolkit's CMake cache, a shared
# staging or dist dir gets overwritten or deleted by the other toolkit's
# run, and a shared test log lets one toolkit's results satisfy the other's
# publish gate). <cuda-tag> is the "cu133" form; <variant> is optional.
# Fails (exit 1, message on stderr) on a malformed tag or variant.
gpu_tuned_cuda_subdir() {
    local base="$1" cuda_tag="$2" variant="${3:-}"
    if [[ -z "${base}" ]]; then
        echo "ERROR: gpu_tuned_cuda_subdir: base dir is empty." >&2
        return 1
    fi
    if [[ ! "${cuda_tag}" =~ ^cu[0-9]{3,4}$ ]]; then
        echo "ERROR: gpu_tuned_cuda_subdir: cuda tag '${cuda_tag}' is not of the form cu<digits> (e.g. cu133)." >&2
        return 1
    fi
    if [[ -z "${variant}" ]]; then
        echo "${base}/${cuda_tag}"
    elif [[ "${variant}" =~ ^[a-z0-9_-]+$ ]]; then
        echo "${base}/${cuda_tag}/${variant}"
    else
        echo "ERROR: gpu_tuned_cuda_subdir: variant '${variant}' is malformed." >&2
        return 1
    fi
}

# gpu_tuned_out_dir <kind> <repo-root> <cuda-tag> [<variant>] — an output directory in the
# per-toolkit tree, tuned/build/<cuda-tag>/ (gitignored via build/), the layout raft and cuvs use
# (changed 2026-10-12 from cpp/build/<cuda>/<variant> and dist/<cuda>/<variant>):
#   build    -> <repo-root>/tuned/build/<cuda-tag>/cmake      the one fixed compile path per toolkit
#   dist     -> <repo-root>/tuned/build/<cuda-tag>/dist       built wheels/tarballs
#   dist shared -> <repo-root>/tuned/build/<cuda-tag>/dist-shared   a SIBLING of dist, never inside
#                   it: wheel.sh clears dist before copying the shared wheels in from here
#   releases -> <repo-root>/tuned/build/<cuda-tag>/releases   generated release inputs (checksums,
#                   test logs); the tracked RELEASE_NOTES_*.md stay in tuned/releases/
# There is no variant level: two variants never share a build tree (gpu_tuned_claim_toolkit_tree
# refuses it). The fixed path is what lets ccache hit and keeps ninja's log for timings. <variant>
# is accepted for source compatibility and only validated; "shared" selects dist-shared. Repos with
# a different layout (faiss) call gpu_tuned_cuda_subdir directly. Fails on an unknown kind or a
# malformed tag or variant.
gpu_tuned_out_dir() {
    local kind="$1" root="$2" cuda_tag="$3" variant="${4:-}" base
    base="$(gpu_tuned_cuda_subdir "${root}/tuned/build" "${cuda_tag}" "${variant}")" || return 1
    base="${base%/"${variant}"}"
    case "${kind}" in
        build) echo "${base}/cmake" ;;
        dist)
            if [[ "${variant}" == shared ]]; then echo "${base}/dist-shared"; else echo "${base}/dist"; fi
            ;;
        releases) echo "${base}/releases" ;;
        *)
            echo "ERROR: gpu_tuned_out_dir: unknown kind '${kind}' (expected build, dist or releases)." >&2
            return 1
            ;;
    esac
}

# gpu_tuned_claim_toolkit_tree <repo-root> <cuda-tag> <variant> — create tuned/build/<cuda-tag>/ and
# record which variant owns it in .variant. With no variant level in the layout, a tree last used
# by another variant would silently mix their objects; this refuses instead (a separate checkout,
# or a different machine, is the way to build another variant). Idempotent for the same variant.
gpu_tuned_claim_toolkit_tree() {
    local root="$1" cuda_tag="$2" variant="$3" dir owner
    [[ -n "${variant}" ]] || { echo "ERROR: gpu_tuned_claim_toolkit_tree: a variant is required." >&2; return 1; }
    dir="$(gpu_tuned_cuda_subdir "${root}/tuned/build" "${cuda_tag}")" || return 1
    mkdir -p "${dir}"
    if [[ -f "${dir}/.variant" ]]; then
        owner="$(cat "${dir}/.variant")"
        if [[ "${owner}" != "${variant}" ]]; then
            echo "ERROR: gpu_tuned_claim_toolkit_tree: ${dir} was built for variant '${owner}', not '${variant}'. Use a separate checkout for another variant." >&2
            return 1
        fi
    else
        printf '%s\n' "${variant}" > "${dir}/.variant"
    fi
}

# gpu_tuned_wheel_version <wheel-path> <pkg-name-prefix> — extracts the
# full version string from a built wheel's filename: the segment between
# "<pkg-name-prefix>-" and the next "-", e.g.
# "flash_attn-2.7.2.post1+cu133-cp312-cp312-linux_aarch64.whl" with prefix
# "flash_attn" -> "2.7.2.post1+cu133". <pkg-name-prefix> is inlined into a
# sed pattern as-is (no regex-escaping) -- fine for the plain
# alnum/underscore package names used across this fleet, not a general-
# purpose escape-anything helper. Callers strip any "+local" segment
# themselves (${VERSION%%+*} -- trivial bash, not worth a function) when
# they need a release-tag-safe base version instead of the full one.
# Consolidates a regex independently duplicated 3 times across
# flash-attention's, flash-attention-vllm's, and vllm's own wheel.sh/
# release.sh.
gpu_tuned_wheel_version() {
    local wheel_path="$1" pkg_prefix="$2" wheel_basename version
    wheel_basename="$(basename "${wheel_path}")"
    version="$(printf '%s' "${wheel_basename}" | sed -E "s/^${pkg_prefix}-([^-]+)-.*/\\1/")"
    if [[ "${version}" == "${wheel_basename}" ]]; then
        echo "ERROR: gpu_tuned_wheel_version: could not extract a version from '${wheel_basename}' (expected it to start with '${pkg_prefix}-')." >&2
        return 1
    fi
    echo "${version}"
}

# gpu_tuned_require_clean_tree — refuses (returns 1) unless the git checkout in
# the current directory has no uncommitted changes to tracked files. Called by
# gpu_tuned_publish_release, so a published build always matches the commit its
# build-info stamp names (a dirty tree stamps " dirty"). Untracked files are
# ignored: build output lands there and would make every build dirty. There is
# deliberately no override; local test builds don't publish. Prints which tree
# it checked, because a few release scripts do not cd to the repo root first.
gpu_tuned_require_clean_tree() {
    local top changes
    if ! top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
        echo "ERROR: gpu_tuned_require_clean_tree: $(pwd) is not inside a git checkout, so a clean tree cannot be shown. Run from the repo root." >&2
        return 1
    fi
    changes="$(git status --porcelain --untracked-files=no 2>/dev/null || true)"
    if [ -n "${changes}" ]; then
        echo "ERROR: refusing to publish from a dirty tree: ${top}" >&2
        echo "  tracked files differ from HEAD ($(git rev-parse --short HEAD 2>/dev/null || echo '?')), so the build would not match its stamped commit:" >&2
        printf '%s\n' "${changes}" | head -10 | sed 's/^/    /' >&2
        [ "$(printf '%s\n' "${changes}" | wc -l)" -le 10 ] || echo "    ..." >&2
        echo "  Commit or stash these, rebuild, then publish." >&2
        return 1
    fi
    echo "OK: clean tracked tree at ${top} ($(git rev-parse --short HEAD 2>/dev/null || echo '?'))"
}

# gpu_tuned_check_wheel_label <wheel-path> -- refuses (returns 1) unless the wheel's file name
# carries a date-form local version: <public>+[<scm>.]<variant>.cu<cuda>.<YYYYMMDD>[.<seq>] with a
# real calendar date and no ".0" sequence (docs/VERSIONING.md). Reads the file NAME only, so it
# runs before anything is uploaded. The same rule as tools/wheel_version_audit.py's DATED class
# (tests/test_wheel_version_audit.py cross-checks the two). GPU_TUNED_ALLOW_COUNTER_LABEL=1 also
# accepts the retired <variant>.cu<cuda>.tuning.<N> counter, for a repo not yet migrated; it says
# so loudly. Anything else (no label, platform-only +cu133, legacy tuning.vN) is refused.
gpu_tuned_check_wheel_label() {
    local name version local_part date
    name="$(basename "${1:-}")"
    if [[ ! "${name}" =~ ^[A-Za-z0-9_.]+-([^-]+)-.+\.whl$ ]]; then
        echo "ERROR: gpu_tuned_check_wheel_label: '${name}' is not a wheel file name." >&2
        return 1
    fi
    version="${BASH_REMATCH[1]}"
    if [[ "${version}" != *+* ]]; then
        echo "ERROR: gpu_tuned_check_wheel_label: ${name} has no local version label (+<variant>.cu<cuda>.<YYYYMMDD>); refusing to publish an unlabelled build." >&2
        return 1
    fi
    local_part="${version#*+}"
    if [[ "${local_part}" =~ ^([a-z][a-z0-9]*\.)*[a-z][a-z0-9]*\.cu[0-9]+\.([1-9][0-9]{7})(\.[1-9][0-9]*)?$ ]]; then
        date="${BASH_REMATCH[2]}"
        if gpu_tuned_valid_date "${date}"; then return 0; fi
        echo "ERROR: gpu_tuned_check_wheel_label: ${name} carries ${date}, which is not a real calendar date." >&2
        return 1
    fi
    if [[ "${GPU_TUNED_ALLOW_COUNTER_LABEL:-}" == 1 && "${local_part}" =~ ^([a-z][a-z0-9]*\.)*[a-z][a-z0-9]*\.cu[0-9]+\.tuning\.(0|[1-9][0-9]*)$ ]]; then
        echo "WARNING: gpu_tuned_check_wheel_label: ${name} uses the retired tuning.N counter label (GPU_TUNED_ALLOW_COUNTER_LABEL=1); migrate this repo to the date form." >&2
        return 0
    fi
    echo "ERROR: gpu_tuned_check_wheel_label: ${name} local version '${local_part}' is not <variant>.cu<cuda>.<YYYYMMDD>[.<seq>] (docs/VERSIONING.md)." >&2
    return 1
}

# gpu_tuned_smoke_wheel <wheel> <dist-name> <import-name> [<stamp-section> <stamp-library>]
# -- install a built wheel into a CLEAN throwaway venv and load it once, before anything is
# published. Nothing from the build tree, the build venv or the repo is on the path: the probe
# runs with `python -I` from an empty directory, so it sees only what a user of the wheel would.
# Checks, in order, each failing loudly:
#   1. the file name carries a date-form label (gpu_tuned_check_wheel_label);
#   2. the wheel's python tag fits the interpreter that will load it;
#   3. it installs, and the venv holds exactly ONE <dist-name> distribution at exactly the
#      wheel's version (a stock wheel pulled in as a dependency would show up here);
#   4. `import <import-name>` works, its __version__ is the wheel's version, and it is loaded from
#      inside the venv;
#   5. if <stamp-section> and <stamp-library> are given, the build-info stamp in the installed
#      <stamp-library> names that version (gpu_tuned_verify_build_info);
#   6. for import-name torch: CUDA is usable, torch.version.cuda is the release the label's cu<NNN>
#      names, a small GPU matmul is correct, and (when GPU_TUNED_SMOKE_EXPECT_CAP=<major.minor> is
#      set) the device capability is that one.
# Needs network for the wheel's pure-python dependencies unless GPU_TUNED_SMOKE_FIND_LINKS=<dir>
# is set (then `--no-index --find-links`). GPU_TUNED_SMOKE_SKIP_LABEL=1 skips step 1 and says so,
# for a wheel built before the date form; the skip is printed, never counted as a pass.
# GPU_TUNED_SMOKE_KEEP=1 keeps the venv and prints its path.
gpu_tuned_smoke_wheel() {
    local wheel="${1:-}" dist="${2:-}" imp="${3:-}" section="${4:-}" stamp_lib="${5:-}"
    local fn="gpu_tuned_smoke_wheel"
    if [[ -z "${wheel}" || -z "${dist}" || -z "${imp}" ]]; then
        echo "ERROR: ${fn}: usage: ${fn} <wheel> <dist-name> <import-name> [<stamp-section> <stamp-library>]" >&2
        return 1
    fi
    [[ -f "${wheel}" ]] || { echo "ERROR: ${fn}: ${wheel} is not a file." >&2; return 1; }
    local base version local_part
    base="$(basename "${wheel}")"
    version="$(gpu_tuned_wheel_version "${wheel}" "${dist//-/_}")" || return 1

    if [[ "${GPU_TUNED_SMOKE_SKIP_LABEL:-}" == 1 ]]; then
        echo "SKIP: ${fn}: version label check (GPU_TUNED_SMOKE_SKIP_LABEL=1)"
    else
        gpu_tuned_check_wheel_label "${wheel}" || return 1
    fi

    local pytag interp_tag
    pytag="$(printf '%s' "${base}" | sed -E 's/^[^-]+-[^-]+-([^-]+)-.*/\1/')"
    interp_tag="$(python3 -c 'import sys; print(f"cp{sys.version_info[0]}{sys.version_info[1]}")')" || return 1
    if [[ "${pytag}" == cp* && "${pytag}" != "${interp_tag}" ]]; then
        echo "ERROR: ${fn}: ${base} is built for ${pytag} but python3 is ${interp_tag}; the smoke test would load nothing." >&2
        return 1
    fi

    local venv work rc=0
    work="$(mktemp -d)"
    venv="${work}/venv"
    python3 -m venv "${venv}" || { rm -rf "${work}"; return 1; }
    local pip_args=(install --quiet)
    if [[ -n "${GPU_TUNED_SMOKE_FIND_LINKS:-}" ]]; then
        pip_args+=(--no-index --find-links "${GPU_TUNED_SMOKE_FIND_LINKS}" --find-links "$(dirname "${wheel}")")
    fi
    # GPU_TUNED_SMOKE_PIN="torch==2.15.0+gb10.cu134.20261012" (space-separated requirements) pins
    # dependencies the wheel only names loosely (torch>=...), and GPU_TUNED_SMOKE_EXTRA_LINKS=<dir>
    # adds a directory holding those exact wheels while the index stays available for everything
    # else. Without them a loose torch requirement resolves to stock torch from PyPI and the smoke
    # test would exercise a pairing nobody ships.
    local pins=()
    if [[ -n "${GPU_TUNED_SMOKE_PIN:-}" ]]; then
        read -r -a pins <<< "${GPU_TUNED_SMOKE_PIN}"
    fi
    [[ -z "${GPU_TUNED_SMOKE_EXTRA_LINKS:-}" ]] || pip_args+=(--find-links "${GPU_TUNED_SMOKE_EXTRA_LINKS}")
    echo "smoke: installing ${base} into a clean venv${pins[*]:+ (pinned: ${pins[*]})}"
    if ! env -u PYTHONPATH -u PYTHONHOME "${venv}/bin/python" -m pip "${pip_args[@]}" "${wheel}" "${pins[@]}" >"${work}/pip.log" 2>&1; then
        echo "ERROR: ${fn}: pip could not install ${base}:" >&2
        tail -15 "${work}/pip.log" >&2
        rm -rf "${work}"
        return 1
    fi

    mkdir "${work}/empty"
    local probe="${work}/probe.out"
    ( cd "${work}/empty" && env -u PYTHONPATH -u PYTHONHOME "${venv}/bin/python" -I - "${dist}" "${imp}" >"${probe}" 2>"${work}/probe.err" <<'PY'
import importlib
import importlib.metadata as md
import re
import sys

dist, imp = sys.argv[1:3]
norm = lambda s: re.sub(r"[-_.]+", "-", s).lower()
print("dists=" + ",".join(sorted(d.version for d in md.distributions() if norm(d.metadata["Name"] or "") == norm(dist))))
mod = importlib.import_module(imp)
print("module_version=" + str(getattr(mod, "__version__", "")))
print("module_file=" + str(getattr(mod, "__file__", "")))
if imp == "torch":
    cuda = mod.cuda
    print("cuda_available=" + str(cuda.is_available()))
    print("cuda_version=" + str(mod.version.cuda))
    if cuda.is_available():
        print("capability=%d.%d" % cuda.get_device_capability(0))
        a = mod.arange(16, dtype=mod.float32, device="cuda").reshape(4, 4)
        print("matmul_ok=" + str(bool(mod.allclose((a @ a).cpu(), a.cpu() @ a.cpu()))))
PY
    ) || rc=$?
    if [[ ${rc} -ne 0 ]]; then
        echo "ERROR: ${fn}: loading ${imp} from the clean venv failed (exit ${rc}):" >&2
        tail -15 "${work}/probe.err" >&2
        [[ "${GPU_TUNED_SMOKE_KEEP:-}" == 1 ]] && echo "venv kept: ${venv}" >&2 || rm -rf "${work}"
        return 1
    fi

    local key val dists="" modver="" modfile="" cuda_avail="" cuda_ver="" cap="" mm=""
    while IFS== read -r key val; do
        case "${key}" in
            dists) dists="${val}" ;; module_version) modver="${val}" ;; module_file) modfile="${val}" ;;
            cuda_available) cuda_avail="${val}" ;; cuda_version) cuda_ver="${val}" ;;
            capability) cap="${val}" ;; matmul_ok) mm="${val}" ;;
        esac
    done <"${probe}"

    local problems=()
    [[ "${dists}" == "${version}" ]] || problems+=("installed ${dist} versions are '${dists}', expected exactly '${version}'")
    # A package whose __version__ is a static string (no local label) is checked against the base
    # version only, with GPU_TUNED_SMOKE_MODULE_VERSION=base; the installed distribution's version
    # (checked above) still has to match the full label exactly.
    local want_modver="${version}"
    [[ "${GPU_TUNED_SMOKE_MODULE_VERSION:-}" == base ]] && want_modver="${version%%+*}"
    [[ "${modver}" == "${want_modver}" ]] || problems+=("${imp}.__version__ is '${modver}', expected '${want_modver}'")
    [[ "${modfile}" == "${venv}"/* ]] || problems+=("${imp} loaded from '${modfile}', not from inside the clean venv")
    if [[ -n "${section}" && -n "${stamp_lib}" ]]; then
        local lib
        lib="$(find "${venv}" -name "${stamp_lib}" -not -type l 2>/dev/null | head -1)"
        if [[ -z "${lib}" ]]; then
            problems+=("stamp library ${stamp_lib} not found in the installed wheel")
        elif ! gpu_tuned_verify_build_info "${lib}" "${dist}" "${version}" "${section}" >/dev/null 2>"${work}/stamp.err"; then
            problems+=("build-info stamp in ${stamp_lib}: $(tr '\n' ' ' <"${work}/stamp.err")")
        fi
    fi
    if [[ "${imp}" == torch ]]; then
        local label_cuda
        label_cuda="$(printf '%s' "${version}" | sed -nE 's/.*\.cu([0-9]+)\..*/\1/p')"
        [[ "${cuda_avail}" == True ]] || problems+=("torch.cuda.is_available() is '${cuda_avail}'")
        if [[ -n "${label_cuda}" ]]; then
            [[ "${cuda_ver/./}" == "${label_cuda}" ]] || problems+=("torch.version.cuda is '${cuda_ver}' but the label says cu${label_cuda}")
        fi
        [[ "${mm}" == True ]] || problems+=("GPU matmul check returned '${mm}'")
        if [[ -n "${GPU_TUNED_SMOKE_EXPECT_CAP:-}" && "${cap}" != "${GPU_TUNED_SMOKE_EXPECT_CAP}" ]]; then
            problems+=("device capability is '${cap}', expected ${GPU_TUNED_SMOKE_EXPECT_CAP}")
        fi
    fi

    if [[ "${GPU_TUNED_SMOKE_KEEP:-}" == 1 ]]; then echo "venv kept: ${venv}"; else rm -rf "${work}"; fi
    if [[ ${#problems[@]} -gt 0 ]]; then
        local p
        for p in "${problems[@]}"; do echo "ERROR: ${fn}: ${p}" >&2; done
        return 1
    fi
    echo "OK: ${fn}: ${base} installs and loads cleanly (${imp} ${modver}${cap:+, device ${cap}, cuda ${cuda_ver}})"
}

# gpu_tuned_publish_release <owner/repo> <tag> <title> <notes-or-@notes-file>
# [asset-spec ...] — publish a GitHub release via `gh release create`,
# always targeting the "tuned-builds" branch (every consumer in this fleet
# always does; call `gh release create` directly for the rare exception).
# <notes-or-@notes-file>: pass literal notes text, or "@<path>"
# (curl-style) to use --notes-file <path> instead -- covers raft's own
# release.sh/wheel.sh/raft_wheel_librmm_shared.sh, which choose between a
# generated notes file and an inline fallback string. Each <asset-spec> is
# passed through as-is to `gh release create` (its own "<path>#<label>"
# attachment syntax) -- pass as many as needed, including via an expanded
# array (`"${ASSETS[@]}"`). Requires at least one asset: a release with
# nothing attached is always a caller mistake in this fleet (forgot to
# build/package first), not a legitimate case.
#
# Refuses to publish from a dirty tree (gpu_tuned_require_clean_tree), run
# against the current directory's checkout, before anything reaches `gh`.
#
# Consolidates a call independently hand-written 12 times across 10 repos
# (raft alone 3x) -- see
# ~/.claude/design/tuned-common-consolidation-candidates.md finding #1.
gpu_tuned_publish_release() {
    local repo="$1" tag="$2" title="$3" notes="$4"
    shift 4
    gpu_tuned_require_clean_tree || return 1
    local asset path
    for asset in "$@"; do
        path="${asset%%#*}"
        if [[ "${path}" == *.whl ]]; then
            gpu_tuned_check_wheel_label "${path}" || return 1
        fi
    done
    if [[ $# -eq 0 ]]; then
        echo "ERROR: gpu_tuned_publish_release: no assets given (at least one is required)." >&2
        return 1
    fi
    local notes_args=(--notes "${notes}")
    if [[ "${notes}" == @* ]]; then
        notes_args=(--notes-file "${notes#@}")
    fi
    if ! gh release create "${tag}" \
        --repo "${repo}" \
        --title "${title}" \
        --target "tuned-builds" \
        "${notes_args[@]}" \
        "$@"; then
        return 1
    fi
    echo "OK: published ${repo}@${tag} -- https://github.com/${repo}/releases/tag/${tag}"
}

# gpu_tuned_verify_venv <venv-dir> <repo-root> — sanity-checks an existing
# venv before build.sh/wheel.sh reuse it, instead of silently building on
# top of corruption. Catches two concrete failure modes hit in practice: a
# venv effectively copied from another repo (bin/pip's shebang -- an
# absolute path baked in at creation by both `python3 -m venv` and `uv
# venv` alike -- resolves outside this venv entirely), and a stray
# <repo-root>/*.egg-info or build/**/CMakeCache.txt left pointing at a
# different repo, either of which silently shadows/misdirects a real
# build. Does not check pyvenv.cfg's `command=` key -- `uv venv` doesn't
# write one, only `python3 -m venv` does.
gpu_tuned_verify_venv() {
    local venv_dir="$1" repo_root="$2"
    local pip_shebang
    pip_shebang="$(head -1 "${venv_dir}/bin/pip" 2>/dev/null | sed -n 's/^#!//p')"
    if [[ -z "${pip_shebang}" || "${pip_shebang}" != "${venv_dir}"/* ]]; then
        echo "ERROR: gpu_tuned_verify_venv: ${venv_dir}/bin/pip's shebang ('${pip_shebang:-<unreadable>}') does not resolve inside ${venv_dir} -- this venv looks copied from another repo. Delete and rebuild: rm -rf ${venv_dir}" >&2
        return 1
    fi

    # <pkg>.egg-info at repo root is a normal, expected artifact -- both
    # `pip install -e .` and `python3 -m build` (re)write one as part of
    # every build in this fleet, which is why it's gitignored everywhere.
    # Its mere presence isn't a problem; only STALE content is: if it's
    # left over from an install into some other/since-deleted venv, its
    # version can silently shadow the real one for anything resolving
    # importlib.metadata from repo_root's cwd. Compare against what's
    # actually installed in *this* venv and fail only on a mismatch.
    local egg_dir pkg_name egg_version installed_version
    for egg_dir in "${repo_root}"/*.egg-info; do
        [[ -d "${egg_dir}" ]] || continue
        pkg_name="$(basename "${egg_dir}" .egg-info)"
        # `|| true`: pip show exits 1 for a package not installed yet (a fresh venv), and a missing
        # PKG-INFO fails sed; both mean "nothing to compare" (empty is handled below), but under
        # set -e + pipefail the failed assignment would abort the caller instead.
        egg_version="$(sed -n 's/^Version: //p' "${egg_dir}/PKG-INFO" 2>/dev/null | head -1 || true)"
        installed_version="$("${venv_dir}/bin/pip" show "${pkg_name}" 2>/dev/null | sed -n 's/^Version: //p' || true)"
        if [[ -n "${egg_version}" && -n "${installed_version}" && "${egg_version}" != "${installed_version}" ]]; then
            echo "ERROR: gpu_tuned_verify_venv: ${egg_dir}/PKG-INFO's Version (${egg_version}) does not match ${venv_dir}'s installed ${pkg_name} (${installed_version}) -- stale metadata, likely left over from a different/deleted venv. Delete it: rm -rf ${egg_dir}" >&2
            return 1
        fi
    done

    local cmake_cache cached_home
    while IFS= read -r cmake_cache; do
        cached_home="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "${cmake_cache}")"
        if [[ -n "${cached_home}" && "${cached_home}" != "${repo_root}" ]]; then
            echo "ERROR: gpu_tuned_verify_venv: ${cmake_cache}'s CMAKE_HOME_DIRECTORY (${cached_home}) does not match this repo (${repo_root}) -- this build/ dir looks copied from another repo. Delete it: rm -rf ${repo_root}/build" >&2
            return 1
        fi
    done < <(find "${repo_root}/build" -name 'CMakeCache.txt' 2>/dev/null || true)

    return 0
}

# gpu_tuned_audit_pinned <pip-cmd> <pkg>=<expected-local-tag> [...] —
# prints each package's installed version, and WARNs (not fatal -- callers
# decide whether to treat it as an error) if a tuned build's local-version
# tag isn't present in what's actually installed, e.g. an untuned
# torch/flashinfer wheel silently shadowing the tuned one via a later,
# unrelated pip install. <pip-cmd> is the pip to inspect -- a venv's
# bin/pip, or `python3 -m pip --user` for flashinfer's shared ~/.local.
#
# `|| true` on the `pip show` pipeline: pip show exits 1 for a package
# that isn't installed -- a normal, expected outcome here (the
# "not installed" branch below), not a real error -- but every caller in
# this fleet runs under `set -o pipefail`, which would otherwise propagate
# that exit 1 out of the pipe-to-sed and abort the whole calling script.
# Confirmed the hard way: flashinfer's build.sh died silently, mid-audit,
# on exactly this the first time it ran flashinfer-cubin (correctly, not
# installed) through gpu_tuned_audit_stray below.
gpu_tuned_audit_pinned() {
    local pip_cmd="$1"
    shift
    local spec pkg tag installed
    for spec in "$@"; do
        pkg="${spec%%=*}"
        tag="${spec#*=}"
        installed="$(${pip_cmd} show "${pkg}" 2>/dev/null | sed -n 's/^Version: //p' || true)"
        if [[ -z "${installed}" ]]; then
            echo "  ${pkg}: not installed"
        elif [[ "${installed}" != *"${tag}"* ]]; then
            echo "WARNING: gpu_tuned_audit_pinned: ${pkg} ${installed} does not carry expected tag '${tag}' -- a non-tuned build may have silently replaced it." >&2
        else
            echo "  ${pkg}: ${installed} (OK)"
        fi
    done
}

# gpu_tuned_audit_stray <pip-cmd> <pkg> [...] — WARNs (not fatal) if any of
# the named packages are installed at all. For packages known to cause
# trouble just by being present, not because of a version conflict, but
# because they aren't part of this fleet's actual dependency chain and can
# trip an unrelated runtime version check (see: flashinfer-cubin).
gpu_tuned_audit_stray() {
    local pip_cmd="$1"
    shift
    local pkg installed
    for pkg in "$@"; do
        installed="$(${pip_cmd} show "${pkg}" 2>/dev/null | sed -n 's/^Version: //p' || true)"
        if [[ -n "${installed}" ]]; then
            echo "WARNING: gpu_tuned_audit_stray: ${pkg} ${installed} is installed but isn't part of this fleet's dependency chain -- consider: ${pip_cmd} uninstall ${pkg}" >&2
        fi
    done
    return 0
}

# gpu_tuned_local_version <variant> <cuda-compact> <tuning-count> -- prints
# the canonical PEP 440 local-version label for a tuned wheel:
#   <variant>.cu<cuda-compact>.tuning.<count>     e.g. gb10.cu134.tuning.34
# This is the ONE place that format is defined; every wheel script calls it
# rather than hand-building the string. Rules enforced (see
# docs/VERSIONING.md for the reasoning and sources):
#   - dot-separated, lowercase alphanumerics only. PEP 440 normalizes "-"
#     and "_" to "." and lowercases, so any other form makes the wheel
#     filename differ from the string we built (tags/titles then disagree).
#   - the counter is its own PURELY NUMERIC segment ("tuning.34", not
#     "tuning.v34" / "tuned34"): numeric segments compare as integers, a
#     fused letter+digit segment compares as text (v100 sorts below v9).
#   - the counter is canonical decimal (no leading zeros): PEP 440
#     normalizes numeric segments, so "007" becomes "7" and a filename
#     containing "007" no longer matches its own metadata (real-world
#     failure: NVIDIA's Jetson torch wheels with "nv24.08", rejected by uv).
# Errors (return 1, message on stderr) rather than emitting a bad label.
gpu_tuned_local_version() {
    local variant="${1:-}" cuda="${2:-}" count="${3:-}"
    if [[ ! "${variant}" =~ ^[a-z][a-z0-9]*$ ]]; then
        echo "ERROR: gpu_tuned_local_version: variant '${variant}' must be lowercase alphanumeric (e.g. gb10)." >&2
        return 1
    fi
    if [[ ! "${cuda}" =~ ^[0-9]+$ ]]; then
        echo "ERROR: gpu_tuned_local_version: cuda-compact '${cuda}' must be digits only (e.g. 134 for CUDA 13.4)." >&2
        return 1
    fi
    if [[ ! "${count}" =~ ^(0|[1-9][0-9]*)$ ]]; then
        echo "ERROR: gpu_tuned_local_version: tuning count '${count}' must be a canonical decimal integer (no leading zeros, no letters): PEP 440 normalizes numeric segments, so a padded count would not match its own wheel filename. See docs/VERSIONING.md." >&2
        return 1
    fi
    echo "${variant}.cu${cuda}.tuning.${count}"
}

# gpu_tuned_tuning_label <version-string> -- prints the "tuning.<N>" part of
# a tuned version (e.g. "0.7.0+gb10.cu134.tuning.149" -> "tuning.149"), or
# nothing (still exit 0) if the version doesn't carry one -- e.g. a wheel
# built before the marker existed, or the legacy "tuning.v<N>" form
# (see docs/VERSIONING.md, "Backfill"). Never fails: callers run under
# `set -o pipefail`, where a no-match grep would otherwise abort them.
gpu_tuned_tuning_label() {
    printf '%s' "${1:-}" | grep -oE 'tuning\.[0-9]+' | head -1 || true
}

# gpu_tuned_valid_date <YYYYMMDD> -- succeeds only for an 8-digit date that is a
# real calendar day and does not start with 0 (a leading zero is stripped by
# PEP 440 normalization, so it would not match its own wheel filename). The date
# is round-tripped through `date -u -d` and compared, not trusted on exit code.
gpu_tuned_valid_date() {
    local d="${1:-}"
    [[ "${d}" =~ ^[1-9][0-9]{7}$ ]] || return 1
    [ "$(date -u -d "${d:0:4}-${d:4:2}-${d:6:2}" +%Y%m%d 2>/dev/null || true)" = "${d}" ]
}

# gpu_tuned_local_version_dated <variant> <cuda-compact> <YYYYMMDD> [<seq>] --
# prints the date-form PEP 440 local label: <variant>.cu<cuda>.<YYYYMMDD>[.<seq>]
# e.g. "0.7.0+gb10.cu134.20261010" and, for a second build the same day,
# "0.7.0+gb10.cu134.20261010.1". Replaces "<variant>.cu<cuda>.tuning.<N>" (user
# decision 2026-10-11, docs/VERSIONING.md); gpu_tuned_local_version is kept for
# consumers that have not migrated.
#
# <seq> is the build's sequence within its date: 0 (the default) is the first
# build and is OMITTED from the label; 1, 2, ... are appended. It must be a
# canonical integer (no leading zeros). A ".0" label is never produced because
# PEP 440 sorts "<date>.0" above "<date>", which would make it a second spelling
# of the first build. The native release tag renders the same integer in full
# (v0.<date>.<seq>, so ".0" there); both come from one sequence value.
gpu_tuned_local_version_dated() {
    local variant="${1:-}" cuda="${2:-}" date="${3:-}" seq="${4:-0}"
    if [[ ! "${variant}" =~ ^[a-z][a-z0-9]*$ ]]; then
        echo "ERROR: gpu_tuned_local_version_dated: variant '${variant}' must be lowercase alphanumeric (e.g. gb10)." >&2
        return 1
    fi
    if [[ ! "${cuda}" =~ ^[0-9]+$ ]]; then
        echo "ERROR: gpu_tuned_local_version_dated: cuda-compact '${cuda}' must be digits only (e.g. 134 for CUDA 13.4)." >&2
        return 1
    fi
    if ! gpu_tuned_valid_date "${date}"; then
        echo "ERROR: gpu_tuned_local_version_dated: date '${date}' must be a real calendar date as YYYYMMDD, not starting with 0." >&2
        return 1
    fi
    if [[ ! "${seq}" =~ ^(0|[1-9][0-9]*)$ ]]; then
        echo "ERROR: gpu_tuned_local_version_dated: sequence '${seq}' must be a canonical integer (0 = first build of the day, no leading zeros)." >&2
        return 1
    fi
    if [ "${seq}" = "0" ]; then
        echo "${variant}.cu${cuda}.${date}"
    else
        echo "${variant}.cu${cuda}.${date}.${seq}"
    fi
}

# gpu_tuned_date_label <version-string> -- prints the "<YYYYMMDD>[.<seq>]" label
# at the END of a date-form tuned version (e.g. "0.7.0+gb10.cu134.20261010.1" ->
# "20261010.1"), or nothing (still exit 0) if the version does not end that way.
# Anchored on the "<variant>.cu<cuda>." that precedes it, because without the old
# "tuning" marker a bare digit match would also hit a CUDA segment or setuptools_scm's
# g<sha>. A ".0" sequence and an impossible calendar date are not labels. Never
# fails (callers run under pipefail).
gpu_tuned_date_label() {
    local v="${1:-}" label=""
    if [[ "${v}" =~ \.cu[0-9]+\.([1-9][0-9]{7}(\.[1-9][0-9]*)?)$ ]]; then
        label="${BASH_REMATCH[1]}"
        gpu_tuned_valid_date "${label:0:8}" || label=""
    elif [[ "${v}" =~ ^v0\.([1-9][0-9]{7})\.(0|[1-9][0-9]*)-[a-z][a-z0-9]*-cu[0-9]+$ ]]; then
        # native release tag v0.<date>.<seq>-<variant>-cu<cuda>; seq 0 is the bare date
        label="${BASH_REMATCH[1]}"
        local seq="${BASH_REMATCH[2]}"   # saved first: gpu_tuned_valid_date's own regex overwrites BASH_REMATCH
        gpu_tuned_valid_date "${label}" || label=""
        [ -z "${label}" ] || [ "${seq}" = 0 ] || label="${label}.${seq}"
    fi
    [ -z "${label}" ] || printf '%s\n' "${label}"
    return 0
}

# gpu_tuned_native_tag <variant> <cuda-tag> <label> -- the release tag of a native (non-wheel)
# build: v0.<YYYYMMDD>.<seq>-<variant>-<cuda-tag>, e.g. v0.20261011.0-gb10-cu134. <label> is
# "<YYYYMMDD>[.<seq>]" from gpu_tuned_allocate_date_label; the sequence is always written here
# (0 for a bare date), where a wheel label omits it. gpu_tuned_date_label reads the tag back.
gpu_tuned_native_tag() {
    local variant="${1:-}" cuda_tag="${2:-}" label="${3:-}" date seq
    date="${label%%.*}"
    seq="$(gpu_tuned_label_seq "${label}")"
    if [[ ! "${variant}" =~ ^[a-z][a-z0-9]*$ ]] || [[ ! "${cuda_tag}" =~ ^cu[0-9]+$ ]] \
        || ! gpu_tuned_valid_date "${date}" || [[ ! "${seq}" =~ ^(0|[1-9][0-9]*)$ ]] \
        || [[ "${label}" != "${date}" && ( "${seq}" = 0 || "${label}" != "${date}.${seq}" ) ]]; then
        echo "ERROR: gpu_tuned_native_tag: need <variant> <cuNNN> <YYYYMMDD[.seq]>, got '${variant}' '${cuda_tag}' '${label}'." >&2
        return 1
    fi
    printf 'v0.%s.%s-%s-%s\n' "${date}" "${seq}" "${variant}" "${cuda_tag}"
}

# gpu_tuned_nvcc_compact [cuda-home] -- the CUDA release that <cuda-home>/bin/nvcc reports,
# without the dot ("134" for 13.4, "1310" for 13.10), for the <cuda> part of a wheel label.
# <cuda-home> defaults to $CUDA_HOME. Reads the nvcc that will really compile, not a directory
# name, so the label cannot disagree with the build; a wheel script that also lets setup.py
# read nvcc (vllm) gets the same answer in both places. Not truncated: vllm's old setup.py cut
# it to three characters, which would turn 13.10 into "131". Fails loudly if nvcc is absent
# or its output cannot be read.
gpu_tuned_nvcc_compact() {
    local home="${1:-${CUDA_HOME:-}}" out rel
    if [ -z "${home}" ]; then
        echo "ERROR: gpu_tuned_nvcc_compact: no CUDA home given and CUDA_HOME is not set." >&2
        return 1
    fi
    if [ ! -x "${home}/bin/nvcc" ]; then
        echo "ERROR: gpu_tuned_nvcc_compact: ${home}/bin/nvcc is not an executable." >&2
        return 1
    fi
    out="$("${home}/bin/nvcc" --version 2>/dev/null || true)"
    rel="$(printf '%s\n' "${out}" | grep -oE 'release [0-9]+\.[0-9]+' | head -1 | awk '{print $2}' || true)"
    if [[ ! "${rel}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: gpu_tuned_nvcc_compact: cannot read a 'release X.Y' from ${home}/bin/nvcc --version." >&2
        return 1
    fi
    printf '%s\n' "${rel/./}"
}

# gpu_tuned_head_date [dir] -- prints the UTC committer date of HEAD as YYYYMMDD: the
# date a build of this commit is labelled with, so rebuilding the same commit reproduces
# its label. Read with TZ=UTC and --date=format-local, NOT --date=format: the latter uses
# the commit's own recorded timezone, which is a day off whenever a commit was made late in
# the evening west of UTC (23:30-07:00 is the next day in UTC). Not the wall clock, and the
# environment's TZ cannot change it.
gpu_tuned_head_date() {
    local dir="${1:-.}" d
    d="$(TZ=UTC git -C "${dir}" log -1 --format=%cd --date=format-local:%Y%m%d HEAD 2>/dev/null || true)"
    if ! gpu_tuned_valid_date "${d}"; then
        echo "ERROR: gpu_tuned_head_date: cannot read a valid HEAD commit date in ${dir} (got '${d}')." >&2
        return 1
    fi
    printf '%s\n' "${d}"
}

# gpu_tuned_taken_date_labels [dir] [remote] -- one "<YYYYMMDD>[.<seq>]" per line for every
# date label already carried by a release tag in <remote> (default origin) or locally.
# Tags are read with `git ls-remote`, not `gh release list` (which pages at 30 and needs auth);
# a GitHub release is a git tag, so it is listed. Fails if the remote cannot be read: a silent
# fallback to local tags could hand out a sequence that is already published.
gpu_tuned_taken_date_labels() {
    local dir="${1:-.}" remote="${2:-origin}" remote_tags local_tags t
    if ! remote_tags="$(git -C "${dir}" ls-remote --tags "${remote}" 2>/dev/null)"; then
        echo "ERROR: gpu_tuned_taken_date_labels: cannot read tags from remote '${remote}' in ${dir}, so an unused sequence cannot be chosen. Check the network, or choose it yourself with GPU_TUNED_LABEL_SEQ=<n>." >&2
        return 1
    fi
    local_tags="$(git -C "${dir}" tag --list)"
    {
        printf '%s\n' "${remote_tags}" | awk '{print $2}' | sed 's#^refs/tags/##; s#\^{}$##'
        printf '%s\n' "${local_tags}"
    } | sort -u | while IFS= read -r t; do gpu_tuned_date_label "${t}"; done | sort -u
}

# gpu_tuned_next_seq <YYYYMMDD> -- reads the taken labels on stdin and prints the LOWEST
# sequence (0, 1, 2, ...) whose label is not taken: 0 is the bare date, n is "<date>.<n>".
# Lowest-unused, not highest-plus-one, so a gap is filled and the answer does not depend on
# order. The sequence is per date across the repo (a second build that day gets .1 even for a
# different CUDA tag), which keeps one integer per build date.
gpu_tuned_next_seq() {
    local date="${1:-}" taken label n=0
    if ! gpu_tuned_valid_date "${date}"; then
        echo "ERROR: gpu_tuned_next_seq: '${date}' is not a valid YYYYMMDD date." >&2
        return 1
    fi
    taken="$(cat)"
    while :; do
        if [ "${n}" = 0 ]; then label="${date}"; else label="${date}.${n}"; fi
        grep -qxF -- "${label}" <<< "${taken}" || break
        n=$((n + 1))
    done
    printf '%s\n' "${n}"
}

# gpu_tuned_label_seq <label> -- the sequence integer of a "<YYYYMMDD>[.<seq>]" label
# (0 for a bare date). One integer renders as the wheel label (0 omitted) and, later, as the
# native tag v0.<date>.<seq> (0 written).
gpu_tuned_label_seq() {
    local label="${1:-}"
    if [[ "${label}" == *.* ]]; then printf '%s\n' "${label#*.}"; else printf '0\n'; fi
}

# gpu_tuned_allocate_date_label [dir] [remote] -- prints the label for a build of HEAD:
# "<YYYYMMDD>" for the first build of that UTC date, "<YYYYMMDD>.<n>" after. The date is
# gpu_tuned_head_date; the sequence is the lowest unused one among the tags in <remote>.
# GPU_TUNED_LABEL_SEQ=<n> skips the lookup and uses n (a canonical integer): for dev builds
# that will never be published (seq 0, no network) and for an offline override. Fails loudly,
# never guesses, if the remote cannot be read and no override is given.
gpu_tuned_allocate_date_label() {
    local dir="${1:-.}" remote="${2:-origin}" date seq taken
    date="$(gpu_tuned_head_date "${dir}")" || return 1
    if [ -n "${GPU_TUNED_LABEL_SEQ:-}" ]; then
        if [[ ! "${GPU_TUNED_LABEL_SEQ}" =~ ^(0|[1-9][0-9]*)$ ]]; then
            echo "ERROR: gpu_tuned_allocate_date_label: GPU_TUNED_LABEL_SEQ='${GPU_TUNED_LABEL_SEQ}' must be a canonical integer (0 = first build of the day, no leading zeros)." >&2
            return 1
        fi
        seq="${GPU_TUNED_LABEL_SEQ}"
    else
        taken="$(gpu_tuned_taken_date_labels "${dir}" "${remote}")" || return 1
        seq="$(printf '%s\n' "${taken}" | gpu_tuned_next_seq "${date}")" || return 1
    fi
    if [ "${seq}" = 0 ]; then printf '%s\n' "${date}"; else printf '%s.%s\n' "${date}" "${seq}"; fi
}

# gpu_tuned_build_local_version <variant> [dir] [remote] -- the complete tuned local-version
# suffix for a build of HEAD: <variant>.cu<cuda>.<YYYYMMDD>[.<seq>], e.g. gb10.cu134.20261011.
# The one place a wheel script gets its label: <cuda> from the nvcc that will compile
# (gpu_tuned_nvcc_compact, needs CUDA_HOME), date and sequence from gpu_tuned_allocate_date_label
# (which reads <remote>'s tags; GPU_TUNED_LABEL_SEQ=<n> skips that, e.g. =0 for a dev build that
# is never published), assembled by gpu_tuned_local_version_dated. Fails loudly at any step.
gpu_tuned_build_local_version() {
    local variant="${1:-}" dir="${2:-.}" remote="${3:-origin}" cuda label
    cuda="$(gpu_tuned_nvcc_compact)" || return 1
    label="$(gpu_tuned_allocate_date_label "${dir}" "${remote}")" || return 1
    gpu_tuned_local_version_dated "${variant}" "${cuda}" "${label%%.*}" "$(gpu_tuned_label_seq "${label}")"
}

# gpu_tuned_jobs -- the default parallel job count for a build: the largest prime not above
# nproc-2, so the desktop session and other builds keep a couple of cores and a memory-heavy nvcc
# fan-out is not at the very maximum (20 cores -> 17, 12 -> 7, 8 -> 5, 4 -> 2, 3 or fewer -> 1).
# The prime is a house preference, not a technical requirement. Callers keep their own override:
#   JOBS="${MAX_JOBS:-$(gpu_tuned_jobs)}". GPU_TUNED_NPROC replaces nproc (for tests).
gpu_tuned_jobs() {
    local n d
    n=$(( ${GPU_TUNED_NPROC:-$(nproc)} - 2 ))
    (( n >= 2 )) || { echo 1; return 0; }
    for (( ; n > 2; n-- )); do
        for (( d = 2; d * d <= n; d++ )); do
            (( n % d == 0 )) && continue 2
        done
        break
    done
    echo "${n}"
}

# gpu_tuned_ninja_timing <ninja-log> <offset-bytes> <out-tsv> [<strip-prefix>] -- per-target build
# timings from ninja's own log, for builds that run CMake+Ninja (pytorch, vllm, flash-attention...).
# Take the log's size (wc -c) BEFORE the build and pass it as <offset-bytes>: ninja appends to the
# log across runs, so only the lines after the offset belong to this build. Writes one line per
# target built in this run to <out-tsv>, in the same shape tuned/build.sh in zbrad/nccl writes:
#   <seconds>\t<kind>\t<target>\t0       kind = nvcc (.cu.o), cxx (.cc/.cpp/.c .o), link (.so/.a), other
# and prints "Timing: <n> units, wall <s>s, summed unit time <s>s" plus the 10 slowest. Ninja records
# a target once per run, so a target rebuilt twice in one run cannot occur; "wall" is the span from
# the first start to the last end in the log. Fails (and writes nothing) if the log is missing, is
# shorter than the offset, or holds no new targets (a no-op build): say so, never report zeros.
gpu_tuned_ninja_timing() {
    local log="${1:-}" offset="${2:-}" out="${3:-}" strip="${4:-}" size
    if [[ -z "${log}" || -z "${out}" || ! "${offset}" =~ ^[0-9]+$ ]]; then
        echo "ERROR: gpu_tuned_ninja_timing: usage: <ninja-log> <offset-bytes> <out-tsv> [<strip-prefix>]" >&2
        return 1
    fi
    [[ -f "${log}" ]] || { echo "ERROR: gpu_tuned_ninja_timing: no ninja log at ${log}" >&2; return 1; }
    size="$(wc -c < "${log}")"
    if [[ "${size}" -lt "${offset}" ]]; then
        echo "ERROR: gpu_tuned_ninja_timing: ${log} is smaller (${size}) than the recorded offset (${offset}); it was replaced during the build." >&2
        return 1
    fi
    tail -c +"$((offset + 1))" "${log}" | awk -F'\t' -v strip="${strip}" '
        /^#/ || NF < 4 { next }
        {
            s = $1 + 0; e = $2 + 0; name = $4
            if (strip != "" && index(name, strip) == 1) name = substr(name, length(strip) + 1)
            kind = "other"
            if (name ~ /\.cu\.o$/) kind = "nvcc"
            else if (name ~ /\.(cc|cpp|cxx|c)\.o$/) kind = "cxx"
            else if (name ~ /\.(so|a)(\.[0-9.]+)?$/) kind = "link"
            printf "%.1f\t%s\t%s\t0\n", (e - s) / 1000, kind, name
        }' > "${out}.tmp"
    if [[ ! -s "${out}.tmp" ]]; then
        rm -f "${out}.tmp"
        echo "ERROR: gpu_tuned_ninja_timing: no targets were built after offset ${offset} in ${log} (a no-op build, or the wrong log)." >&2
        return 1
    fi
    mv "${out}.tmp" "${out}"
    tail -c +"$((offset + 1))" "${log}" | awk -F'\t' '
        /^#/ || NF < 4 { next }
        { n++; sum += ($2 - $1) / 1000; if (min == "" || $1 < min) min = $1; if ($2 > max) max = $2 }
        END { printf "Timing: %d units, wall %.0fs, summed unit time %.0fs\n", n, (max - min) / 1000, sum }'
    echo "Slowest units:"
    sort -t$'\t' -k1,1 -rn "${out}" | head -10 | awk -F'\t' '{ printf "  %7.1fs  %-6s %s\n", $1, $2, $3 }'
}

# ---- unique shared-object identities -------------------------------------------------
#
# Why: the dynamic linker matches a needed library by its SONAME. A tuned package that ships
# libggml.so.0 shares that identity with a stock llama.cpp, so (verified with toy libraries in
# tests/test_common.sh) a stock binary can silently bind OUR library depending on directory
# order, our binary can bind THEIRS when LD_LIBRARY_PATH points there (RUNPATH loses to it), and
# installing both into one directory makes the second overwrite the first. A renamed file with a
# renamed SONAME and rewritten DT_NEEDED is immune to all three. patchelf does it at package time;
# no upstream-tracked build file changes.

# The mark inserted before ".so". One constant, so changing the convention is one edit.
GPU_TUNED_SO_MARK="-tuned"

# gpu_tuned_tuned_so_name <so-file-name> -- prints the tuned form of a shared-object file name:
# libggml.so.0.23.0 -> libggml-tuned.so.0.23.0, libllama-server-impl.so -> libllama-server-impl-tuned.so.
# Idempotent (an already-marked name is unchanged). Fails on a name that is not lib*.so[.N...].
gpu_tuned_tuned_so_name() {
    local n="${1:-}"
    if [[ ! "${n}" =~ ^(lib.+)\.so((\.[0-9]+)*)$ ]]; then
        echo "ERROR: gpu_tuned_tuned_so_name: '${n}' is not a lib*.so[.N...] name." >&2
        return 1
    fi
    if [[ "${BASH_REMATCH[1]}" == *"${GPU_TUNED_SO_MARK}" ]]; then
        printf '%s\n' "${n}"
    else
        printf '%s\n' "${BASH_REMATCH[1]}${GPU_TUNED_SO_MARK}.so${BASH_REMATCH[2]}"
    fi
}

# gpu_tuned_rename_sonames <stage-dir> <manifest> [keep-regex] -- give the shared objects that
# THIS build produced a unique identity. <manifest> lists, one per line, the file names in
# <stage-dir> that are our own build output (select by provenance, never by name pattern: a
# pattern misses whatever upstream adds next). Each is renamed to its tuned name and gets a
# tuned SONAME; then the DT_NEEDED of every ELF in <stage-dir> that names a renamed file is
# rewritten, executables included. Names matching [keep-regex] are left alone (for builds that
# load backends by filename; none today). Files not in the manifest (bundled system libraries
# such as libnccl) are never touched. Idempotent. Run after RUNPATH is set; re-check any
# build-info stamp (gpu_tuned_verify_build_info) afterwards, patchelf rewrites the files.
# Prints "old -> new" per rename.
gpu_tuned_rename_sonames() {
    local stage="${1:-}" manifest="${2:-}" keep="${3:-}" name new f soname d
    declare -A map=()
    if [ ! -d "${stage}" ] || [ ! -f "${manifest}" ]; then
        echo "ERROR: gpu_tuned_rename_sonames: need a stage directory and a manifest file." >&2
        return 1
    fi
    command -v patchelf >/dev/null 2>&1 || { echo "ERROR: gpu_tuned_rename_sonames: patchelf is not installed." >&2; return 1; }
    while IFS= read -r name; do
        [ -n "${name}" ] || continue
        if [ -n "${keep}" ] && [[ "${name}" =~ ${keep} ]]; then continue; fi
        if [ ! -f "${stage}/${name}" ] && [ ! -f "${stage}/$(gpu_tuned_tuned_so_name "${name}")" ]; then
            echo "ERROR: gpu_tuned_rename_sonames: '${name}' is in the manifest but not in ${stage}." >&2
            return 1
        fi
        new="$(gpu_tuned_tuned_so_name "${name}")" || return 1
        map["${name}"]="${new}"
    done < "${manifest}"
    # pass 1: rename the files and give each a tuned SONAME
    for name in "${!map[@]}"; do
        new="${map[${name}]}"
        if [ "${name}" != "${new}" ] && [ -e "${stage}/${name}" ]; then
            if [ -e "${stage}/${new}" ]; then
                echo "ERROR: gpu_tuned_rename_sonames: ${new} already exists in ${stage}, so ${name} cannot be renamed to it." >&2
                return 1
            fi
            mv "${stage}/${name}" "${stage}/${new}"
            echo "${name} -> ${new}"
        fi                                                  # else: already renamed by an earlier run
        soname="$(patchelf --print-soname "${stage}/${new}" 2>/dev/null || true)"
        if [ -n "${soname}" ]; then
            if [ -n "${keep}" ] && [[ "${soname}" =~ ${keep} ]]; then continue; fi
            patchelf --set-soname "$(gpu_tuned_tuned_so_name "${soname}")" "${stage}/${new}"
        fi
    done
    # pass 2: rewrite DT_NEEDED in every ELF in the stage
    for f in "${stage}"/*; do
        [ -f "${f}" ] && [ ! -L "${f}" ] || continue
        patchelf --print-needed "${f}" >/dev/null 2>&1 || continue
        while IFS= read -r d; do
            [ -n "${d}" ] || continue
            if [ -n "${map[${d}]:-}" ] && [ "${map[${d}]}" != "${d}" ]; then
                patchelf --replace-needed "${d}" "${map[${d}]}" "${f}"
            fi
        done < <(patchelf --print-needed "${f}" 2>/dev/null)
    done
}

# gpu_tuned_so_names_cmake <out-file> -- write the CMake include that gives the shared libraries of
# a build unique "-tuned" identities AT BUILD TIME (OUTPUT_NAME <name>-tuned, so the file name, the
# SONAME, every DT_NEEDED and the generated CMake export files all carry it), without editing any
# upstream source. Pass it to CMake as
#   -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=<out-file> "-DTUNED_SO_TARGETS=<target;target...>"
# TUNED_SO_TARGETS names the CMake targets to mark (targets that are absent, imported or not shared
# libraries are skipped; one already ending in -tuned is left alone). The marking runs deferred at
# the end of the top-level directory, after fetched dependencies exist and before generation. The
# mark is GPU_TUNED_SO_MARK. Writes the same bytes every time.
gpu_tuned_so_names_cmake() {
    local out="${1:-}"
    [ -n "${out}" ] || { echo "ERROR: gpu_tuned_so_names_cmake: need an output file." >&2; return 1; }
    cat > "${out}" <<CMAKE
# Generated by gpu_tuned_so_names_cmake (tuned-common). Do not edit.
function(tuned_mark_shared_libraries)
  foreach(tgt IN LISTS TUNED_SO_TARGETS)
    if(NOT TARGET \${tgt})
      continue()
    endif()
    get_target_property(_type \${tgt} TYPE)
    get_target_property(_imported \${tgt} IMPORTED)
    if(_imported OR NOT _type STREQUAL "SHARED_LIBRARY")
      continue()
    endif()
    get_target_property(_out \${tgt} OUTPUT_NAME)
    if(NOT _out)
      set(_out \${tgt})
    endif()
    if(NOT _out MATCHES "${GPU_TUNED_SO_MARK}\$")
      set_target_properties(\${tgt} PROPERTIES OUTPUT_NAME "\${_out}${GPU_TUNED_SO_MARK}")
    endif()
    message(STATUS "tuned: \${tgt} -> lib\${_out}${GPU_TUNED_SO_MARK}.so")
  endforeach()
endfunction()
cmake_language(DEFER DIRECTORY "\${CMAKE_SOURCE_DIR}" CALL tuned_mark_shared_libraries)
CMAKE
}

# gpu_tuned_cmake_ignore_pip_prefixes -- print (no newline) the semicolon list of user-site pip prefixes
# a build must not search: ~/.local/lib/python*/site-packages itself and every package directory
# under it that ships CMake config (lib*/cmake or share/cmake). Pass it as
#   -DCMAKE_IGNORE_PREFIX_PATH=<list>
# Why: pip wheels such as librmm install complete CMake packages (nvtx3, rmm, rapids_logger ...), and
# CMake finds them through the site-packages directories. A dependency found there is not fetched, so
# it is not installed with our package either: the tarball's rmm-dependencies.cmake then asks for
# nvtx3 that the package does not contain, and the build also silently depends on whatever stock
# wheel happens to be installed. Prints nothing when there is no user site-packages.
gpu_tuned_cmake_ignore_pip_prefixes() {
    local sp d out=() IFS
    for sp in "${HOME}"/.local/lib/python*/site-packages; do
        [ -d "${sp}" ] || continue
        out+=("${sp}")
        for d in "${sp}"/*/; do
            d="${d%/}"
            compgen -G "${d}/lib*/cmake" >/dev/null || compgen -G "${d}/share/cmake" >/dev/null || continue
            out+=("${d}")
        done
    done
    IFS=';'
    printf '%s' "${out[*]}"
}

# gpu_tuned_warn_pip_cmake_packages -- warn loudly (stderr) when user-site pip wheels ship CMake
# packages (the ones gpu_tuned_cmake_ignore_pip_prefixes tells CMake to ignore), naming each wheel and
# printing the pip command that removes them. The build is safe either way (they are ignored); the
# warning is that a stock wheel is installed that could shadow our libraries at run time and that
# nothing built here is tested against. Only wheels whose names clash with what this fleet ships are
# named (GPU_TUNED_CONFLICT_WHEEL_RE, default librmm, rapids_logger, libkvikio, libraft, libcuvs);
# unrelated CMake-shipping wheels such as torch are never suggested for removal. Always returns 0; prints nothing when there are none.
gpu_tuned_warn_pip_cmake_packages() {
    local ign sp d di base names=() pkg
    ign="$(gpu_tuned_cmake_ignore_pip_prefixes)"
    [ -n "${ign}" ] || return 0
    while IFS= read -r d; do
        [ -n "${d}" ] || continue
        case "${d}" in */site-packages) continue ;; esac
        sp="${d%/*}"; pkg="${d##*/}"
        for di in "${sp}"/*.dist-info; do
            [ -f "${di}/RECORD" ] || continue
            if grep -q "^${pkg}/" "${di}/RECORD" 2>/dev/null; then
                base="${di##*/}"; base="${base%%-*}"
                [[ "${base}" =~ ${GPU_TUNED_CONFLICT_WHEEL_RE:-^(librmm|rapids_logger|libkvikio|libraft|libcuvs)} ]] && names+=("${base}")
                break
            fi
        done
    done < <(printf '%s\n' "${ign}" | tr ';' '\n')
    [ "${#names[@]}" -gt 0 ] || return 0
    {
        echo ""
        echo "################################################################################"
        echo "WARNING: stock pip wheels that ship CMake packages are installed in your user site-packages:"
        printf '    %s\n' "${names[@]}"
        echo "This build IGNORES them (CMAKE_IGNORE_PREFIX_PATH), so it is not affected. But they carry the"
        echo "stock librmm/nvtx3/... names this fleet replaces, and could be loaded in place of ours at run time."
        case " ${names[*]} " in *" librmm"*) echo "nvtx3: librmm bundles its own nvtx3. That is NOT the tuned copy: the fleet fetches nvtx3 at the pinned"; echo "rapids-cmake, tests against it and ships it. The wheel's copy is unpinned and untested here (an equal version number"; echo "does not show the contents match), so a build that used it would not be the build that was tested." ;; esac
        echo "Remove them with:"
        echo "    python3 -m pip uninstall -y ${names[*]}"
        echo "(anything that depends on them, e.g. rmm-cu13 or pylibraft, must go too; pip lists dependents)"
        echo "################################################################################"
        echo ""
    } >&2
    return 0
}

# gpu_tuned__nvtx3_from_pip <cache> <ignore-list> -- true if the cache's nvtx3_DIR is under an ignored pip prefix.
gpu_tuned__nvtx3_from_pip() {
    local v p
    v="$(grep -E '^nvtx3_DIR:[A-Z]+=' "${1}" | head -1)"; v="${v#*=}"
    while IFS= read -r p; do
        [ -n "${p}" ] || continue
        case "${v}" in "${p}"|"${p}"/*) return 0 ;; esac
    done < <(printf '%s\n' "${2}" | tr ';' '\n')
    return 1
}

# gpu_tuned_verify_no_pip_cmake_deps <CMakeCache.txt> -- fail (rc 1, names each entry) if any *_DIR or
# *_ROOT entry of a build's CMake cache points into a user-site pip prefix (see
# gpu_tuned_cmake_ignore_pip_prefixes). The ignore list should make that impossible, so this is the
# check that it did: a dependency (nvtx3, rmm ...) resolved from a stock wheel is not fetched, so it is
# missing from the package built from this tree. Run it after configure; a stale cache from before the
# ignore list is caught too (the entry must be unset with -U<var>).
gpu_tuned_verify_no_pip_cmake_deps() {
    local cache="${1:-}" ign p line bad=0
    [ -f "${cache}" ] || { echo "ERROR: gpu_tuned_verify_no_pip_cmake_deps: no such cache file: ${cache}" >&2; return 1; }
    ign="$(gpu_tuned_cmake_ignore_pip_prefixes)"
    [ -n "${ign}" ] || return 0
    while IFS= read -r line; do
        while IFS= read -r p; do
            [ -n "${p}" ] || continue
            case "${line#*=}" in "${p}"|"${p}"/*) echo "ERROR: CMake resolved ${line%%:*} from a pip wheel: ${line#*=}" >&2; bad=1; break ;; esac
        done < <(printf '%s\n' "${ign}" | tr ';' '\n')
    done < <(grep -E '^[A-Za-z0-9_]+_(DIR|ROOT):[A-Z]+=' "${cache}" | grep -vE '^CMAKE_')
    if grep -qE '^nvtx3_DIR:[A-Z]+=' "${cache}" && [ "${bad}" -ne 0 ] && gpu_tuned__nvtx3_from_pip "${cache}" "${ign}"; then
        echo "  nvtx3: this is NOT the tuned copy. The fleet fetches nvtx3 at the pinned rapids-cmake, builds and tests against" >&2
        echo "  that copy and ships it in the package. The wheel's copy is unpinned, untested here and unaligned with the rest of" >&2
        echo "  the tree; an equal version number (both 3.2.0 when this was written) does not show the contents match." >&2
    fi
    [ "${bad}" -eq 0 ] || echo "  Remove the wheel (see gpu_tuned_warn_pip_cmake_packages) and reconfigure with -U<var> for each entry above." >&2
    return "${bad}"
}

# gpu_tuned_verify_consumer_configure <package-dir> <cmake-package>... -- prove the package is usable by a
# consumer: configure a minimal CMake project that does find_package(<name> REQUIRED CONFIG) for each
# name against ONLY <package-dir> (CMAKE_PREFIX_PATH), with the user-site pip prefixes ignored, then
# require that nvtx3_DIR, rmm_DIR and rapids_logger_DIR (those the consumer resolved) point inside
# <package-dir> and that nvtx3_DIR is set. This is the failure a consumer such as zbrad/faiss hits when
# a package leaves a dependency out: its CMake files ask for it and nothing in the package answers.
# Needs cmake; the CUDA toolkit must be findable (find_dependency(CUDAToolkit)). rc 1 and the CMake
# output on failure.
gpu_tuned_verify_consumer_configure() {
    local pkg="${1:-}" tmp rc=0 var val
    shift || true
    [ -d "${pkg}" ] && [ "$#" -gt 0 ] || { echo "ERROR: gpu_tuned_verify_consumer_configure: need <package-dir> and at least one package name." >&2; return 1; }
    pkg="$(cd "${pkg}" && pwd -P)"
    tmp="$(mktemp -d)" || return 1
    {
        printf 'cmake_minimum_required(VERSION 3.26)\nproject(tuned_consumer CXX)\n'
        for var in "$@"; do printf 'find_package(%s REQUIRED CONFIG)\n' "${var}"; done
    } > "${tmp}/CMakeLists.txt"
    if ! cmake -S "${tmp}" -B "${tmp}/b" "-DCMAKE_PREFIX_PATH=${pkg}" "-DCMAKE_IGNORE_PREFIX_PATH=$(gpu_tuned_cmake_ignore_pip_prefixes)" > "${tmp}/log" 2>&1; then
        echo "ERROR: a consumer cannot configure against ${pkg} (find_package $*):" >&2
        sed 's/^/  /' "${tmp}/log" >&2
        rm -rf "${tmp}"; return 1
    fi
    for var in nvtx3_DIR rmm_DIR rapids_logger_DIR; do
        val="$(grep -E "^${var}:[A-Z]+=" "${tmp}/b/CMakeCache.txt" | head -1)"; val="${val#*=}"
        if [ -z "${val}" ] || [[ "${val}" == *-NOTFOUND ]]; then
            [ "${var}" = nvtx3_DIR ] && { echo "ERROR: the consumer never resolved nvtx3 from ${pkg}; the package does not ship it." >&2; rc=1; }
            continue
        fi
        case "${val}" in "${pkg}"/*) ;; *) echo "ERROR: the consumer resolved ${var} outside the package: ${val}" >&2; rc=1 ;; esac
    done
    rm -rf "${tmp}"
    return "${rc}"
}

# gpu_tuned_rename_package <stage-dir> <ours-manifest> <system-manifest|-> <keep-regex> <assume-present-regex> [<ref-dir>...]
# -- the whole package-time rename in one call: gpu_tuned_rename_sonames, then every file under
# each <ref-dir> (CMake import files, pkg-config; typically <stage>/lib/cmake and <stage>/lib/pkgconfig,
# directories that do not exist are skipped) is rewritten so that each renamed manifest name is
# replaced by its tuned name, then it fails if any ref file still names a stock (renamed) name, then
# gpu_tuned_verify_unique_sonames. Idempotent. Prints "old -> new" per rename, indented. The caller
# keeps what is specific to it: building the manifests, and re-checking its build-info stamp
# afterwards (patchelf rewrote the files). A manifest name matching <keep-regex> is left alone.
# Limit: only file names are rewritten (libfoo.so, -l:libfoo.so); a bare pkg-config `-lfoo` names no
# file and is NOT repointed, so a package that ships such a reference needs it fixed by hand.
gpu_tuned_rename_package() {
    local stage="${1:-}" ours="${2:-}" sysman="${3:--}" keep="${4:-}" assume="${5:-}" name new d f bad=0
    shift $(( $# < 5 ? $# : 5 ))
    gpu_tuned_rename_sonames "${stage}" "${ours}" "${keep}" | sed 's/^/  /'
    [ "${PIPESTATUS[0]}" -eq 0 ] || return 1
    while IFS= read -r name; do
        [ -n "${name}" ] || continue
        if [ -n "${keep}" ] && [[ "${name}" =~ ${keep} ]]; then continue; fi
        new="$(gpu_tuned_tuned_so_name "${name}")" || return 1
        [ "${name}" != "${new}" ] || continue
        for d in "$@"; do
            [ -d "${d}" ] || continue
            # the old name as a whole word: not preceded or followed by a name character
            grep -rlE "(^|[^A-Za-z0-9_-])${name//./\\.}([^A-Za-z0-9._-]|\$)" "${d}" 2>/dev/null | while IFS= read -r f; do
                sed -i -E "s#(^|[^A-Za-z0-9_-])${name//./\\.}([^A-Za-z0-9._-]|\$)#\\1${new}\\2#g" "${f}"
            done || true
            if grep -rqE "(^|[^A-Za-z0-9_-])${name//./\\.}([^A-Za-z0-9._-]|\$)" "${d}" 2>/dev/null; then
                echo "VIOLATION: files under ${d} still name the stock ${name}." >&2; bad=1
            fi
        done
    done < "${ours}"
    [ "${bad}" -eq 0 ] || return 1
    gpu_tuned_verify_unique_sonames "${stage}" "${sysman}" "${keep}" "${assume}"
}

# gpu_tuned_verify_unique_sonames <stage-dir> <system-manifest|-> [keep-regex] [assume-present-regex]
# -- the gate; it FAILS CLOSED. Every shared object in <stage-dir> must be exactly one of:
# tuned (file name and SONAME carry the mark), kept (matches [keep-regex]), or a bundled system
# library recorded in <system-manifest> (one name per line; "-" for none). Anything else would
# ship under a shared identity, so a library upstream adds later breaks the package build instead
# of slipping through. It also checks closure: every DT_NEEDED of every ELF must be a file in the
# stage or match [assume-present-regex] (glibc, the driver, the CUDA toolkit...), and a needed name
# carrying the mark must exist in the stage. Prints every violation, returns 1 if any.
gpu_tuned_verify_unique_sonames() {
    local stage="${1:-}" sysman="${2:--}" keep="${3:-}" assume="${4:-}" f n soname d bad=0
    declare -A sysnames=()
    if [ ! -d "${stage}" ]; then echo "ERROR: gpu_tuned_verify_unique_sonames: no such stage directory: ${stage}" >&2; return 1; fi
    if [ "${sysman}" != "-" ]; then
        [ -f "${sysman}" ] || { echo "ERROR: gpu_tuned_verify_unique_sonames: no such system manifest: ${sysman}" >&2; return 1; }
        while IFS= read -r n; do [ -n "${n}" ] && sysnames["${n}"]=1; done < "${sysman}"
    fi
    for f in "${stage}"/*; do
        [ -f "${f}" ] && [ ! -L "${f}" ] || continue
        patchelf --print-needed "${f}" >/dev/null 2>&1 || continue            # not an ELF
        n="$(basename "${f}")"
        if [[ "${n}" =~ ^lib.+\.so(\.[0-9]+)*$ ]]; then
            soname="$(patchelf --print-soname "${f}" 2>/dev/null || true)"
            if [ -n "${sysnames[${n}]:-}" ]; then
                :                                                             # bundled system library, recorded
            elif [ -n "${keep}" ] && [[ "${n}" =~ ${keep} ]]; then
                :                                                             # kept on purpose
            elif [[ "${n}" == *"${GPU_TUNED_SO_MARK}.so"* ]]; then
                if [ -n "${soname}" ] && [[ "${soname}" != *"${GPU_TUNED_SO_MARK}.so"* ]]; then
                    echo "VIOLATION: ${n} is renamed but its SONAME is '${soname}'." >&2; bad=1
                fi
            else
                echo "VIOLATION: ${n} is not tuned, not kept and not a recorded system library: it would ship under a shared identity (SONAME '${soname:-none}')." >&2; bad=1
            fi
        fi
        while IFS= read -r d; do
            [ -n "${d}" ] || continue
            if [ -e "${stage}/${d}" ]; then continue; fi
            if [[ "${d}" == *"${GPU_TUNED_SO_MARK}.so"* ]]; then
                echo "VIOLATION: ${n} needs ${d}, which is not in the stage." >&2; bad=1
            elif [ -n "${assume}" ] && [[ "${d}" =~ ${assume} ]]; then
                continue
            else
                echo "VIOLATION: ${n} needs ${d}, which is neither in the stage nor assumed present on the target." >&2; bad=1
            fi
        done < <(patchelf --print-needed "${f}" 2>/dev/null)
    done
    return "${bad}"
}

# gpu_tuned_check_main_current [repo-dir] -- fails loudly if the tuning counter
# (git rev-list --count main..HEAD, see gpu_tuned_tuning_count) would include
# upstream's commits rather than only ours. That happens when upstream has been
# merged into HEAD but local `main` was not fast-forwarded to `upstream/main`
# afterwards: those commits are in main..HEAD but are not ours. (A plain
# `git fetch upstream` without a merge is fine and does not trip this.)
# Measured exactly: <stale> = count(main..HEAD) - count(HEAD --not main
# upstream/main). Returns 1 with the fix command when <stale> > 0, unless
# GPU_TUNED_ALLOW_STALE_MAIN is set (then a loud warning and return 0). With no
# `upstream` remote or no fetched upstream/main the check cannot run, so it
# warns on stderr and returns 0. A missing local `main` is always an error.
gpu_tuned_check_main_current() {
    local dir="${1:-.}" total ours stale
    if ! git -C "${dir}" rev-parse --verify --quiet refs/heads/main >/dev/null; then
        echo "ERROR: gpu_tuned_check_main_current: no local 'main' branch in ${dir}; the tuning counter is git rev-list --count main..HEAD. Create it with: git fetch upstream main:main" >&2
        return 1
    fi
    if ! git -C "${dir}" remote get-url upstream >/dev/null 2>&1; then
        echo "WARNING: gpu_tuned_check_main_current: no 'upstream' remote in ${dir}; cannot verify local main is current." >&2
        return 0
    fi
    if ! git -C "${dir}" rev-parse --verify --quiet refs/remotes/upstream/main >/dev/null; then
        echo "WARNING: gpu_tuned_check_main_current: upstream/main not fetched in ${dir}; run 'git fetch upstream' so local main can be verified." >&2
        return 0
    fi
    total="$(git -C "${dir}" rev-list --count main..HEAD)"
    ours="$(git -C "${dir}" rev-list --count HEAD --not main upstream/main)"
    stale=$(( total - ours ))
    if (( stale > 0 )); then
        echo "ERROR: gpu_tuned_check_main_current: local 'main' is stale in ${dir}: the tuning counter (main..HEAD = ${total}) would include ${stale} upstream commit(s); only ${ours} are ours." >&2
        echo "  Fix: git fetch upstream main:main   (fast-forward only), then re-run. See docs/VERSIONING.md." >&2
        if [[ -n "${GPU_TUNED_ALLOW_STALE_MAIN:-}" ]]; then
            echo "WARNING: GPU_TUNED_ALLOW_STALE_MAIN is set; continuing with an inflated counter." >&2
            return 0
        fi
        return 1
    fi
}

# gpu_tuned_tuning_count [repo-dir] -- prints the tuning counter N for a wheel's
# tuning.<N> label: git rev-list --count main..HEAD, after
# gpu_tuned_check_main_current has confirmed it counts only our commits. Use it
# instead of running git rev-list yourself; it fails loudly on a stale main.
gpu_tuned_tuning_count() {
    local dir="${1:-.}"
    gpu_tuned_check_main_current "${dir}" || return 1
    git -C "${dir}" rev-list --count main..HEAD
}

# --- Loud failures ---------------------------------------------------------
# Every consumer script runs under `set -euo pipefail`, where a failing
# command -- notably a no-match grep inside a $(...) assignment -- aborts the
# script with NO output at all. That has bitten this fleet repeatedly
# (release.sh's tuning-label grep, audit_pinned/audit_stray, venv checks).
# Sourcing this file installs an ERR trap so an abort always says which
# command failed, where, and from what call stack. Quiet by design when
# errexit is not active (a `set +e` region, or a command whose failure the
# caller handles with `||`/`if`, never fires an ERR trap in the first
# place). Opt out with GPU_TUNED_NO_ERR_TRAP=1; an ERR trap the script
# already installed itself is left alone.
gpu_tuned_on_err() {
    local rc="$1" cmd="$2" i
    [[ $- == *e* ]] || return 0
    {
        echo "[tuned] ERROR: command failed (exit ${rc}): ${cmd}"
        for (( i = 1; i < ${#BASH_SOURCE[@]}; i++ )); do
            echo "[tuned]   at ${BASH_SOURCE[i]}:${BASH_LINENO[i-1]} (${FUNCNAME[i]:-main})"
        done
    } >&2
}

if [[ -z "${GPU_TUNED_NO_ERR_TRAP:-}" && -z "$(trap -p ERR)" ]]; then
    set -o errtrace
    trap 'gpu_tuned_on_err "$?" "${BASH_COMMAND}"' ERR
fi
