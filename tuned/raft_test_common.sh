#!/bin/bash
# raft_test_common.sh — shared helper for running raft's FULL C++ gtest
# suite (every binary built into a variant's cpp/build-<variant>/gtests/),
# as opposed to raft_regression_test_<variant>.sh's 2 targeted checks for
# known upstream bugs (warpReduce ADL fix, laplacian NZType / SM_121a
# memory-corruption fix). Sourced by each variant's
# raft_full_test_<variant>.sh.

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
        if ! "${bin}"; then
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
