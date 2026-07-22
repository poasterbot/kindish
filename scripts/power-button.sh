#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

VM_PID_FILE="$RUNTIME_DIR/kindish-vm.pid"
VM_QMP_SOCKET="$RUNTIME_DIR/kindish-qmp.sock"

pid_alive "$VM_PID_FILE" || die "start the Kindle VM before pressing its power button"
[[ -S "$VM_QMP_SOCKET" ]] || die "the Kindle VM monitor is unavailable"
command -v socat >/dev/null || die "socat is required; run 'mise run setup'"

{
  printf '%s\n' \
    '{"execute":"qmp_capabilities"}' \
    '{"execute":"system_powerdown"}'
} | socat - "UNIX-CONNECT:$VM_QMP_SOCKET" >/dev/null 2>&1 || \
  die "failed to press the VM's GPIO power button"

printf 'Kindle power button pressed.\n'
