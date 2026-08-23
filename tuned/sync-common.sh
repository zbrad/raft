#!/bin/bash
# sync-common.sh — check or refresh a consumer repo's vendored copy of
# zbrad/tuned-common's shared function library (tuned-common.sh).
#
# Vendored into every consumer alongside its copy of tuned-common.sh (as
# tuned/sync-common.sh for repos with a tuned/ dir, or a repo-root
# tuned-common-sync.sh for repos without one, e.g. ComfyUI/vllm) -- run it
# from there, it self-locates its sibling common.sh/tuned-common.sh.
#
# Usage:
#   sync-common.sh check          — compare local vs zbrad/tuned-common's
#                                    main branch; exit 1 (no changes made)
#                                    if the vendored copy is stale
#   sync-common.sh sync [<ref>]   — fetch <ref> (a commit SHA or branch/tag,
#                                    default: main HEAD), overwrite the
#                                    local vendored copy if content
#                                    differs, and record the synced commit
#
# Never applies an update that fails a basic syntax check (bash -n) --
# refuses and leaves the existing vendored copy untouched.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_RAW_BASE="https://raw.githubusercontent.com/zbrad/tuned-common"
REPO_API_BASE="https://api.github.com/repos/zbrad/tuned-common"

die() { echo "ERROR: $*" >&2; exit 1; }

# Find the vendored file next to this script: tuned/common.sh (the
# convention for repos with build automation) or a repo-root
# tuned-common.sh (ComfyUI/vllm, which have no tuned/ dir).
if [[ -f "${SELF_DIR}/common.sh" ]]; then
    TARGET="${SELF_DIR}/common.sh"
elif [[ -f "${SELF_DIR}/tuned-common.sh" ]]; then
    TARGET="${SELF_DIR}/tuned-common.sh"
else
    die "no vendored common.sh or tuned-common.sh found next to $0 -- expected one alongside this script"
fi
SHA_FILE="${TARGET}.sha"

command -v curl >/dev/null 2>&1 || die "curl not found on PATH"
command -v jq >/dev/null 2>&1 || die "jq not found on PATH"

# resolve_ref <ref> — a commit SHA is returned as-is; a branch/tag name
# (e.g. "main") is resolved to its current commit SHA via the GitHub API,
# so `sync main` always means "whatever main points to right now", not a
# floating ref that would make two runs on different days silently fetch
# different content under the same recorded "ref".
resolve_ref() {
    local ref="$1"
    if [[ "${ref}" =~ ^[0-9a-f]{40}$ ]]; then
        echo "${ref}"
        return
    fi
    curl -fsSL "${REPO_API_BASE}/commits/${ref}" | jq -r '.sha // empty'
}

current_sha() {
    [[ -f "${SHA_FILE}" ]] && cat "${SHA_FILE}" || echo "unknown"
}

cmd="${1:-check}"

case "${cmd}" in
    check)
        latest="$(resolve_ref main)"
        [[ -n "${latest}" ]] || die "could not resolve zbrad/tuned-common main to a commit SHA (network/API issue?)"
        local_sha="$(current_sha)"
        if [[ "${local_sha}" == "${latest}" ]]; then
            echo "OK: ${TARGET} is up to date (${local_sha})"
            exit 0
        else
            echo "STALE: ${TARGET} is at ${local_sha}, zbrad/tuned-common main is at ${latest}"
            echo "       run: $0 sync"
            exit 1
        fi
        ;;
    sync)
        ref="${2:-main}"
        resolved="$(resolve_ref "${ref}")"
        [[ -n "${resolved}" ]] || die "could not resolve ref '${ref}' to a commit SHA"

        echo "Fetching zbrad/tuned-common@${resolved}..."
        tmp="$(mktemp)"
        curl -fsSL -o "${tmp}" "${REPO_RAW_BASE}/${resolved}/tuned-common.sh" || {
            rm -f "${tmp}"
            die "fetch failed for ${REPO_RAW_BASE}/${resolved}/tuned-common.sh"
        }
        bash -n "${tmp}" || {
            rm -f "${tmp}"
            die "fetched file failed a syntax check -- refusing to overwrite ${TARGET}"
        }

        if [[ -f "${TARGET}" ]] && diff -q "${tmp}" "${TARGET}" >/dev/null 2>&1; then
            echo "No content changes (already matches ${resolved})"
            rm -f "${tmp}"
        else
            [[ -f "${TARGET}" ]] && diff -u "${TARGET}" "${tmp}" || true
            mv "${tmp}" "${TARGET}"
            echo "Updated ${TARGET}"
        fi
        echo "${resolved}" > "${SHA_FILE}"
        echo "OK: synced to ${resolved}"
        ;;
    *)
        die "usage: $0 [check|sync [<ref>]]"
        ;;
esac
