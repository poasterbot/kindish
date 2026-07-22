#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

VM_PID_FILE="$RUNTIME_DIR/kindish-vm.pid"
VM_DEBUG_SOCKET="$RUNTIME_DIR/kindish-debug.sock"

pid_alive "$VM_PID_FILE" || die "start the Kindle VM before pressing its power button"
[[ -S "$VM_DEBUG_SOCKET" ]] || die "the Kindle VM diagnostic console is unavailable"
command -v socat >/dev/null || die "socat is required; run 'mise run setup'"

{
  sleep 0.1
  printf '\nlipc-set-prop com.lab126.powerd powerButton 1\n'
  sleep 0.5
} | socat - "UNIX-CONNECT:$VM_DEBUG_SOCKET" >/dev/null 2>&1 || \
  die "failed to send the power-button event to KindleOS"

printf 'Kindle power button pressed.\n'
