#!/bin/bash
# tuned-common.sh — shared build-tooling functions for the GB10/RTX40/RTX50
# "tuned-builds" fleet (pytorch, llama.cpp, flash-attention, flashinfer,
# raft, cuvs, faiss, and downstream consumers like vllm/ComfyUI/open-webui).
#
# Source this file; it defines functions only (no side effects, no exports)
# so it's safe to source before or after a repo's own tuned/env.sh sets its
# device-specific vars. Every function takes its inputs as explicit
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
gpu_tuned_embed_build_info() {
    local target="$1" variant="$2" package="$3" version="$4" hw_label="${5:-${2}}" repo_url="${6:-}" section_override="${7:-}"
    local section tmp
    if [ -n "${section_override}" ]; then
        section="${section_override}"
        [[ "${section}" == .* ]] || section=".${section}"
    else
        section=".$(printf '%s' "${package}" | tr -c 'A-Za-z0-9' '_')_build_info"
    fi
    tmp="$(mktemp)"
    {
        printf '%s-%s build: %s v%s (%s)' "${package}" "${variant}" "${package}" "${version}" "${hw_label}"
        [ -n "${repo_url}" ] && printf ', %s' "${repo_url}"
        printf ', built %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "${tmp}"
    objcopy --remove-section "${section}" "${target}" 2>/dev/null || true
    objcopy --add-section "${section}=${tmp}" "${target}"
    rm -f "${tmp}"
}

# gpu_tuned_protect_torch_pin <venv-dir> <exact-torch-version> — guards a
# venv's tuned (non-PyPI) torch install against being silently swapped out
# by a companion package's exact torch pin (e.g. `pip install torchvision`
# hard-pins torch==2.13.0 and, without this, pip's resolver just
# uninstalls whatever tuned build is there and installs that instead --
# no warning). Writes <venv-dir>/../constraints-gb10.txt (one line: the
# pinned torch version) and <venv-dir>/pip.conf (constraint= pointing at
# it) -- pip reads {sys.prefix}/pip.conf automatically for any
# venv-prefixed `pip`/`python -m pip` invocation, no activation needed.
# Idempotent: safe to call again after rebuilding/reinstalling the tuned
# torch wheel with its new version string.
#
# Effect once wired in: a future `pip install torchvision` (or anything
# else that hard-pins torch) fails loudly with a ResolutionImpossible
# conflict instead of silently downgrading torch. When that happens and
# the package is actually needed: `pip install --no-deps <package>`, then
# manually verify it still works against the tuned torch (a real call on
# a CUDA tensor, not just import -- see zbrad/ComfyUI project memory
# for the torchvision/torchaudio compatibility checks done this way).
gpu_tuned_protect_torch_pin() {
    local venv_dir="$1" torch_version="$2"
    if [[ -z "${venv_dir}" || -z "${torch_version}" ]]; then
        echo "ERROR: gpu_tuned_protect_torch_pin: usage: gpu_tuned_protect_torch_pin <venv-dir> <exact-torch-version>" >&2
        return 1
    fi
    if [[ ! -d "${venv_dir}" ]]; then
        echo "ERROR: gpu_tuned_protect_torch_pin: no such venv dir: ${venv_dir}" >&2
        return 1
    fi
    local repo_dir constraints_file
    repo_dir="$(cd "${venv_dir}/.." && pwd)"
    constraints_file="${repo_dir}/constraints-gb10.txt"

    cat > "${constraints_file}" <<EOF
# Pins the GB10-tuned torch build so any future \`pip install\` in this venv
# is forced to keep it -- without this, pip's resolver treats an exact
# torch pin from a dependency (e.g. torchvision/torchaudio hard-pinning a
# specific torch version) as authoritative and silently uninstalls the
# tuned build in favor of a generic PyPI one. Wired in via
# <venv>/pip.conf's [install] constraint=. Generated by
# gpu_tuned_protect_torch_pin (zbrad/tuned-common) -- rerun it whenever
# the tuned torch wheel is rebuilt/reinstalled to refresh this pin.
torch==${torch_version}
EOF

    cat > "${venv_dir}/pip.conf" <<EOF
[install]
constraint = ${constraints_file}
EOF

    echo "OK: pinned torch==${torch_version} for ${venv_dir} (constraint: ${constraints_file})"
}
