#!/bin/bash
# raft_test_common.sh — shared helper for running raft's FULL C++ gtest
# suite (every binary built into a variant's cpp/build-<variant>/gtests/),
# as opposed to raft_regression_test_<variant>.sh's 2 targeted checks for
# known upstream bugs (warpReduce ADL fix, laplacian NZType / SM_121a
# memory-corruption fix). Sourced by each variant's
# raft_full_test_<variant>.sh.

# Tests skipped under WSL2 only (native Linux still runs them), as
# "<binary>:<gtest pattern>". Raft.InterruptibleOpenMP assumes 10 host threads'
# GPU kernels overlap in real time in launch order; on WSL2 that does not hold
# and it fails ~70% of runs with a varying finished-thread count (3..10), also
# with a 100 ms step instead of 20 ms, so it is not a timing margin. It passes
# on native Linux (GB10). A proper fix is an upstream rewrite of the test.
WSL_SKIPPED_TESTS=("CORE_TEST:Raft.InterruptibleOpenMP")

# gtest_args_for <binary-name>: prints the gtest args for that binary.
gtest_args_for() {
    local name="$1" entry skip=""
    grep -qi microsoft /proc/version 2>/dev/null || return 0
    for entry in "${WSL_SKIPPED_TESTS[@]}"; do
        [[ "${entry%%:*}" == "${name}" ]] && skip+="${skip:+:}${entry#*:}"
    done
    [[ -n "${skip}" ]] && echo "--gtest_filter=-${skip}"
}

# run_full_test_suite <build_dir>
# Runs every executable directly under <build_dir>/gtests/ in turn,
# printing a header before each and a PASS/FAIL summary at the end.
# Returns non-zero if any binary failed (or if none were found) --
# suitable as a gate before raft_wheel_<variant>.sh/publishing.
run_full_test_suite() {
    local build_dir="$1"
    local gtests_dir="${build_dir}/gtests"
    if [[ ! -d "${gtests_dir}" ]]; then
        echo "ERROR: ${gtests_dir} not found -- build the tests first" >&2
        return 1
    fi

    local -a binaries=()
    while IFS= read -r -d '' f; do
        binaries+=("${f}")
    done < <(find "${gtests_dir}" -maxdepth 1 -type f -executable -print0 | sort -z)

    if [[ ${#binaries[@]} -eq 0 ]]; then
        echo "ERROR: no test binaries found under ${gtests_dir}" >&2
        return 1
    fi

    local -a failed=()
    local name bin
    for bin in "${binaries[@]}"; do
        name="$(basename "${bin}")"
        echo "=== ${name} ==="
        local -a args=()
        read -r -a args <<< "$(gtest_args_for "${name}")"
        [[ ${#args[@]} -gt 0 ]] && echo "NOTE: WSL2 -- running with ${args[*]}"
        if ! "${bin}" "${args[@]}"; then
            failed+=("${name}")
        fi
    done

    echo ""
    echo "=== Full test suite summary: $(( ${#binaries[@]} - ${#failed[@]} ))/${#binaries[@]} binaries passed ==="
    if [[ ${#failed[@]} -gt 0 ]]; then
        echo "FAILED: ${failed[*]}" >&2
        return 1
    fi
    echo "All binaries passed."
    return 0
}
