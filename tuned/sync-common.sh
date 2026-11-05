#!/bin/bash
# sync-common.sh — check or refresh a consumer repo's vendored copy of
# zbrad/tuned-common's shared function library (tuned-common.sh) and, when the
# consumer has opted in, its data files (devices/*.conf, toolkits/*.env).
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
#                                    default: main HEAD), bring the local
#                                    vendored copies up to it, and record the
#                                    synced commit
#
# A sync is a MERGE, not an overwrite (added 2026-11-05). The recorded commit in
# <target>.sha is the merge base, so a local edit to a vendored file is told apart
# from an upstream change instead of being silently clobbered:
#
#   local == base                 -> fast-forward to upstream
#   local == upstream             -> nothing to do
#   base == upstream              -> keep the local edits, upstream did not move
#   all three differ              -> git merge-file; a clean merge is applied,
#                                    a conflicting one is REFUSED
#   upstream dropped the file     -> removed only if the local copy is provably
#                                    the one upstream last shipped, else kept
#
# Every file's outcome is written to <target>.sync-report, which is meant to be
# committed with the sync: the report plus git history is the record of what the
# vendor deployment actually did. Nothing is overwritten without the previous
# local content being saved beside it as <file>.local-<sha>.
#
# A refused file makes the run exit 1 and leaves <target>.sha UNCHANGED, so the
# next run still has the right merge base to retry from. Applied files are
# idempotent: on the next run local == upstream, and nothing happens.
#
# Never applies an update that fails a basic syntax check (bash -n) -- that check
# runs on the MERGED result, not just on what was fetched, because a clean
# three-way merge can still produce broken shell.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Overridable so the tests can serve a local tree over file:// instead of GitHub.
REPO_RAW_BASE="${GPU_TUNED_SYNC_RAW_BASE:-https://raw.githubusercontent.com/zbrad/tuned-common}"
REPO_API_BASE="${GPU_TUNED_SYNC_API_BASE:-https://api.github.com/repos/zbrad/tuned-common}"

# A sync that aborts part-way still writes its report: the point of the report is to
# record what the deployment did, and that matters most when it did not finish.
# write_report and the globals it reads are defined below; die is only ever called
# after them at run time.
die() {
    echo "ERROR: $*" >&2
    if [[ -n "${REPORT_FILE:-}" && -n "${REPORT:-}" ]]; then
        ABORTED="$*"
        write_report "${SYNC_NEW_SHA:-unknown}" "${SYNC_BASE_SHA:-unknown}"
    fi
    exit 1
}

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
REPORT_FILE="${TARGET}.sync-report"

command -v curl >/dev/null 2>&1 || die "curl not found on PATH"
command -v jq >/dev/null 2>&1 || die "jq not found on PATH"
# git supplies the three-way merge (git merge-file). Every consumer is a git
# checkout, so this is not a new dependency in practice.
command -v git >/dev/null 2>&1 || die "git not found on PATH (needed for the three-way merge)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

REPORT=""
REFUSED=0
ABORTED=""
report() { REPORT+="$1"$'\n'; }
# status <word> <path> [note] -- one report line, aligned.
status() { report "$(printf '%-10s %s%s' "$1" "$2" "${3:+  -- $3}")"; }

# Data files (devices/*.conf, toolkits/*.env) are vendored into
# <this dir>/common-data/ only when that directory already exists, so a
# consumer opts in with `mkdir tuned/common-data` and repos that keep their
# own device files are untouched.
DATA_DIR="${SELF_DIR}/common-data"

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

# fetch_at <sha> <path> <dest> -- the file's content at that commit.
# rc 0 = fetched, 1 = it did not exist at that commit (a 404 is an ANSWER: the
# file was added later, so there is no merge base for it), 2 = could not tell.
# The three are kept apart deliberately: reading a network failure as "added
# since" would turn a merge into an overwrite.
#
# On a 404 curl has already written the error body to <dest> (there is no -f here, so
# that the status code can be read): callers must not read <dest> unless rc is 0. The
# rm -f below, and the one in vendor_one, are what keep a stale file from being
# mistaken for fetched content -- do not remove either.
fetch_at() {
    local sha="$1" path="$2" dest="$3" code rc=0
    rm -f "${dest}"
    code="$(curl -sSL -o "${dest}" -w '%{http_code}' "${REPO_RAW_BASE}/${sha}/${path}" 2>/dev/null)" || rc=$?
    case "${code}" in
        200) return 0 ;;
        404) return 1 ;;
        000)
            # A file:// base (what the tests use) reports no HTTP status: curl exiting 0
            # with the file written is a hit, its "couldn't open file" (37) is a miss.
            [[ "${rc}" -eq 0 && -f "${dest}" ]] && return 0
            [[ "${rc}" -eq 37 ]] && return 1
            return 2
            ;;
        *) return 2 ;;
    esac
}

# The tree listing normally comes from the GitHub API. The tests point
# GPU_TUNED_SYNC_TREE_JSON at a file instead, because a file:// URL cannot carry the
# API's query string.
tree_json() {
    if [[ -n "${GPU_TUNED_SYNC_TREE_JSON:-}" ]]; then
        cat "${GPU_TUNED_SYNC_TREE_JSON}"
    else
        curl -fsSL "${REPO_API_BASE}/git/trees/$1?recursive=1"
    fi
}

# syntax_ok <path> <file> -- a vendored file must parse as bash before it is installed.
syntax_ok() {
    if bash -n "$2" 2>/dev/null; then return 0; fi
    status REFUSED "$1" "the result failed bash -n; left exactly as it was"
    return 1
}

# vendor_one <path> <local-file> <new-sha> <base-sha> -- bring one vendored file to
# the version at <new-sha> by merging, never by overwriting. <base-sha> is the commit
# this consumer last synced, or "unknown". rc 1 if the file was refused (it is then
# left byte-for-byte as it was); rc 0 otherwise.
vendor_one() {
    local path="$1" dest="$2" new_sha="$3" base_sha="$4"
    local new="${TMP_DIR}/new" base="${TMP_DIR}/base" merged="${TMP_DIR}/merged"
    local short="${new_sha:0:7}" rc=0
    rm -f "${new}" "${base}" "${merged}"

    fetch_at "${new_sha}" "${path}" "${new}" || rc=$?
    case "${rc}" in
        0) ;;
        1) die "${path} is listed at ${new_sha} but is not there -- refusing to guess" ;;
        *) die "fetch failed for ${REPO_RAW_BASE}/${new_sha}/${path}" ;;
    esac

    if [[ ! -f "${dest}" ]]; then
        syntax_ok "${path}" "${new}" || return 1
        mkdir -p "$(dirname "${dest}")"
        cp "${new}" "${dest}"
        status added "${path}"
        return 0
    fi

    if cmp -s "${dest}" "${new}"; then
        status unchanged "${path}"
        return 0
    fi

    # Was the local file the one upstream shipped at the last sync, or has it been
    # edited here? Without the base that question cannot be answered.
    local have_base=0
    if [[ "${base_sha}" != unknown ]]; then
        rc=0
        fetch_at "${base_sha}" "${path}" "${base}" || rc=$?
        case "${rc}" in
            0) have_base=1 ;;
            1) have_base=0 ;;   # added upstream after that commit
            *) die "fetch failed for ${REPO_RAW_BASE}/${base_sha}/${path} (needed as the merge base)" ;;
        esac
    fi

    if [[ "${have_base}" -eq 0 ]]; then
        syntax_ok "${path}" "${new}" || return 1
        diff -u "${dest}" "${new}" || true
        cp "${dest}" "${dest}.local-${short}"
        cp "${new}" "${dest}"
        status updated "${path}" "no merge base, so local edits could not be told apart; previous content saved as ${dest##*/}.local-${short}"
        return 0
    fi

    if cmp -s "${dest}" "${base}"; then
        syntax_ok "${path}" "${new}" || return 1
        diff -u "${dest}" "${new}" || true
        cp "${new}" "${dest}"
        status updated "${path}"
        return 0
    fi

    # Differs from the base as well as from upstream: there are real local edits.
    if cmp -s "${base}" "${new}"; then
        status kept "${path}" "local edits; upstream has not changed since ${base_sha:0:7}"
        return 0
    fi
    if git merge-file -q -p -L local -L "base ${base_sha:0:7}" -L "upstream ${short}" \
        "${dest}" "${base}" "${new}" > "${merged}" 2>/dev/null; then
        syntax_ok "${path}" "${merged}" || return 1
        diff -u "${dest}" "${merged}" || true
        cp "${dest}" "${dest}.local-${short}"
        cp "${merged}" "${dest}"
        status merged "${path}" "local edits kept; previous content saved as ${dest##*/}.local-${short}"
        return 0
    fi
    cp "${new}" "${dest}.upstream-${short}"
    status CONFLICT "${path}" "left exactly as it was; upstream version saved as ${dest##*/}.upstream-${short}"
    return 1
}

# prune_or_keep <path> <local-file> <base-sha> -- upstream no longer ships this file.
# It is removed ONLY when it is provably the copy upstream last shipped here; anything
# else (local edits, no merge base) is kept and reported. Removal is the one thing this
# script does beyond reporting, and it is why the base matters.
prune_or_keep() {
    local path="$1" dest="$2" base_sha="$3" base="${TMP_DIR}/base" rc=0
    rm -f "${base}"
    if [[ "${base_sha}" == unknown ]]; then
        status kept "${path}" "not in upstream; no merge base, so not removed"
        return 0
    fi
    fetch_at "${base_sha}" "${path}" "${base}" || rc=$?
    case "${rc}" in
        2) die "fetch failed for ${REPO_RAW_BASE}/${base_sha}/${path} (needed to decide whether to remove it)" ;;
        1) status kept "${path}" "not in upstream and not at ${base_sha:0:7} either: a local file, not removed" ;;
        0)
            if cmp -s "${dest}" "${base}"; then
                rm -f "${dest}"
                echo "Removed ${dest} (upstream dropped it; the local copy was unedited)"
                status removed "${path}" "upstream dropped it and the local copy was unedited"
            else
                status kept "${path}" "upstream dropped it but the local copy differs from ${base_sha:0:7}, so not removed"
            fi
            ;;
    esac
}

# sync_data <new-sha> <base-sha> — vendor the data files, merging each one.
sync_data() {
    local new_sha="$1" base_sha="$2" paths path listed="" f rel
    paths="$(tree_json "${new_sha}" \
        | jq -r '.tree[] | select(.type == "blob") | .path' \
        | grep -E '^(devices/[^/]+\.conf|toolkits/[^/]+\.env)$' || true)"
    [[ -n "${paths}" ]] || die "no device or toolkit files listed at ${new_sha} -- refusing to treat that as 'upstream dropped them all'"
    while IFS= read -r path; do
        [[ -n "${path}" ]] || continue
        listed+="${path}"$'\n'
        vendor_one "${path}" "${DATA_DIR}/${path}" "${new_sha}" "${base_sha}" || REFUSED=$((REFUSED + 1))
    done <<< "${paths}"
    while IFS= read -r f; do
        [[ -n "${f}" ]] || continue
        rel="${f#"${DATA_DIR}"/}"
        grep -qxF "${rel}" <<< "${listed}" && continue
        prune_or_keep "${rel}" "${f}" "${base_sha}"
    done < <(find "${DATA_DIR}" -type f ! -name '*.local-*' ! -name '*.upstream-*' | sort)
}

write_report() {
    local new_sha="$1" base_sha="$2"
    {
        echo "# sync-common report"
        echo
        echo "Written by sync-common.sh; commit it with the sync. One line per vendored file."
        echo
        echo "when:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "target: ${TARGET##*/}"
        echo "base:   ${base_sha}"
        echo "synced: ${new_sha}"
        if [[ -n "${ABORTED}" ]]; then
            echo "result: ABORTED part-way -- ${ABORTED}"
            echo "        .sha NOT advanced; the lines below are what had already been done."
        elif [[ "${REFUSED}" -ne 0 ]]; then
            echo "result: ${REFUSED} file(s) REFUSED -- .sha NOT advanced, rerun after resolving"
        else
            echo "result: all files resolved"
        fi
        echo
        printf '%s' "${REPORT}"
    } > "${REPORT_FILE}"
    echo "Report: ${REPORT_FILE}"
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
        base="$(current_sha)"
        SYNC_NEW_SHA="${resolved}"; SYNC_BASE_SHA="${base}"

        echo "Fetching zbrad/tuned-common@${resolved} (merge base: ${base})..."
        vendor_one "tuned-common.sh" "${TARGET}" "${resolved}" "${base}" || REFUSED=$((REFUSED + 1))
        [[ -d "${DATA_DIR}" ]] && sync_data "${resolved}" "${base}"

        write_report "${resolved}" "${base}"
        if [[ "${REFUSED}" -ne 0 ]]; then
            echo "ERROR: ${REFUSED} file(s) could not be resolved; ${SHA_FILE##*/} left at ${base}." >&2
            echo "       Resolve them (or delete the local edits) and run sync again; see ${REPORT_FILE##*/}." >&2
            exit 1
        fi
        echo "${resolved}" > "${SHA_FILE}"
        echo "OK: synced to ${resolved}"
        ;;
    *)
        die "usage: $0 [check|sync [<ref>]]"
        ;;
esac
