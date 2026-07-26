#!/bin/bash
# raft_monitor.sh — background health monitors for WSL crash isolation.
# Sourced by raft_full_test_monitored.sh. Reads LOG_DIR and RUN_ID from env.
# All logs go to Windows filesystem (/mnt/c/...) so they survive WSL crash.

LOG_DIR="${LOG_DIR:-/mnt/c/Users/brad_/AppData/Local/Temp/raft-crash-monitor}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
LOGBASE="${LOG_DIR}/${RUN_ID}"

mkdir -p "${LOG_DIR}" || { echo "ERROR: cannot create ${LOG_DIR}" >&2; exit 1; }

{
  echo "=== monitor start: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  echo "RUN_ID=${RUN_ID}  kernel=$(uname -r)  host=$(uname -n)"
} >> "${LOGBASE}-dmesg.log"

# 1. Live kernel ring-buffer (OOM kills, CUDA TDR, dxg errors)
dmesg -W >> "${LOGBASE}-dmesg.log" 2>&1 &
DMESG_PID=$!

# 2. nvidia-smi: SM util, memory, temp, power every 5s
nvidia-smi dmon -s pucvm -d 5 >> "${LOGBASE}-gpu.log" 2>&1 &
GPU_MON_PID=$!

# 3. RAM pressure every 10s
(
  while true; do
    printf '%s ' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    grep -E '^(MemAvailable|SwapFree):' /proc/meminfo | tr '\n' '  '
    echo ""
    sleep 10
  done
) >> "${LOGBASE}-mem.log" 2>&1 &
MEM_MON_PID=$!

echo "Monitors started — logs in ${LOG_DIR}/"
echo "  dmesg : ${LOGBASE}-dmesg.log  (pid ${DMESG_PID})"
echo "  gpu   : ${LOGBASE}-gpu.log    (pid ${GPU_MON_PID})"
echo "  mem   : ${LOGBASE}-mem.log    (pid ${MEM_MON_PID})"