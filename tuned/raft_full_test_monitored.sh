#!/bin/bash
# raft_full_test_monitored.sh <variant>
#
# Instrumented wrapper around the full gtest suite. Identical test logic to
# tuned/full_test.sh but adds:
#   - Per-binary start/finish timestamps on Windows filesystem so logs
#     survive a WSL VM crash
#   - Background dmesg, nvidia-smi, and memory monitors (raft_monitor.sh)
#   - GPU snapshot (VRAM used, temp, power) before and after each binary
#
# Usage:  bash tuned/raft_full_test_monitored.sh <variant>
#   variant: rtx50 | rtx40 | gb10
#
# If WSL crashes mid-run, the last ">>> START" without a "<<< PASS/FAIL"
# in -run.log identifies the culprit binary.

set -euo pipefail

VARIANT="${1:?Usage: $0 <variant>}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export LOG_DIR="/mnt/c/Users/brad_/AppData/Local/Temp/raft-crash-monitor"
export RUN_ID="$(date +%Y%m%d-%H%M%S)-${VARIANT}"
LOGBASE="${LOG_DIR}/${RUN_ID}"

mkdir -p "${LOG_DIR}"

# Run header written to Windows path before monitors start
{
  echo "=== raft monitored test run: ${VARIANT} ==="
  echo "started : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "run_id  : ${RUN_ID}"
  echo "host    : $(uname -n)  kernel: $(uname -r)"
  nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null || true
  free -h
} > "${LOGBASE}-run.log"

echo "Logs: ${LOG_DIR}/${RUN_ID}-*"

# Start background monitors (sets DMESG_PID, GPU_MON_PID, MEM_MON_PID)
# shellcheck source=./raft_monitor.sh
source "${PROJECT_ROOT}/tuned/raft_monitor.sh"

stop_monitors() {
  kill "${DMESG_PID}" "${GPU_MON_PID}" "${MEM_MON_PID}" 2>/dev/null || true
}
trap stop_monitors EXIT

# Locate test binaries
GTESTS_DIR="${PROJECT_ROOT}/cpp/build-${VARIANT}/gtests"
if [[ ! -d "${GTESTS_DIR}" ]]; then
  echo "ERROR: ${GTESTS_DIR} not found — build the tests first" | tee -a "${LOGBASE}-run.log"
  exit 1
fi

BINARIES=()
while IFS= read -r -d '' f; do
  BINARIES+=("$f")
done < <(find "${GTESTS_DIR}" -maxdepth 1 -type f -executable -print0 | sort -z)

if [[ ${#BINARIES[@]} -eq 0 ]]; then
  echo "ERROR: no test binaries found under ${GTESTS_DIR}" | tee -a "${LOGBASE}-run.log"
  exit 1
fi

echo "Running ${#BINARIES[@]} binaries..." | tee -a "${LOGBASE}-run.log"

FAILED=()

for BIN in "${BINARIES[@]}"; do
  NAME="$(basename "${BIN}")"
  BIN_LOG="${LOGBASE}-${NAME}.log"

  # Start marker + GPU snapshot written BEFORE the binary starts
  {
    echo ">>> START ${NAME} $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    nvidia-smi --query-gpu=memory.used,memory.free,temperature.gpu,power.draw \
      --format=csv,noheader 2>/dev/null || true
  } | tee -a "${LOGBASE}-run.log"

  START_T=$(date +%s)

  # Each binary's stdout+stderr to its own log on Windows path;
  # partial output is preserved even if WSL dies during this binary
  if "${BIN}" >> "${BIN_LOG}" 2>&1; then
    STATUS="PASS"
  else
    RC=$?
    STATUS="FAIL(rc=${RC})"
    FAILED+=("${NAME}")
  fi

  ELAPSED=$(( $(date +%s) - START_T ))

  {
    echo "<<< ${STATUS} ${NAME} ${ELAPSED}s $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    nvidia-smi --query-gpu=memory.used,memory.free,temperature.gpu,power.draw \
      --format=csv,noheader 2>/dev/null || true
  } | tee -a "${LOGBASE}-run.log"
done

{
  echo ""
  echo "=== Summary: $(( ${#BINARIES[@]} - ${#FAILED[@]} ))/${#BINARIES[@]} passed ==="
  echo "finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "FAILED: ${FAILED[*]}"
  else
    echo "All binaries passed."
  fi
} | tee -a "${LOGBASE}-run.log"

[[ ${#FAILED[@]} -eq 0 ]]