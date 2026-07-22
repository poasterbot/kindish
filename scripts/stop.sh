#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

VM_PID_FILE="$RUNTIME_DIR/kindish-vm.pid"
VM_QMP_SOCKET="$RUNTIME_DIR/kindish-qmp.sock"
VM_DEBUG_SOCKET="$RUNTIME_DIR/kindish-debug.sock"

"$PROJECT_ROOT/scripts/mtp-stop.sh" >/dev/null 2>&1 || true

if pid_alive "$VM_PID_FILE"; then
  vm_pid=$(<"$VM_PID_FILE")
  if [[ -S "$VM_DEBUG_SOCKET" ]]; then
    {
      sleep 0.2
      printf '\nshutdown -h now\n'
      sleep 1
    } | socat - "UNIX-CONNECT:$VM_DEBUG_SOCKET" >/dev/null 2>&1 || true
  fi
  for _ in {1..600}; do
    kill -0 "$vm_pid" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$vm_pid" 2>/dev/null; then
    if [[ -S "$VM_QMP_SOCKET" ]]; then
      {
        printf '{"execute":"qmp_capabilities"}\n'
        printf '{"execute":"quit"}\n'
      } | socat - "UNIX-CONNECT:$VM_QMP_SOCKET" >/dev/null 2>&1 || true
    else
      kill "$vm_pid" 2>/dev/null || true
    fi
  fi
fi

if pid_alive "$PID_DIR/novnc.pid"; then
  kill "$(<"$PID_DIR/novnc.pid")" 2>/dev/null || true
fi
for stale in \
  "$VM_PID_FILE" \
  "$RUNTIME_DIR/kindish-qmp.sock" \
  "$RUNTIME_DIR/kindish-debug.sock" \
  "$PID_DIR/novnc.pid"; do
  [[ ! -e "$stale" ]] || unlink "$stale"
done
printf 'KindleOS VM stopped. Writable partitions were preserved.\n'
