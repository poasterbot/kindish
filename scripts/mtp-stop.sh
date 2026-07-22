#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

command -v usbip >/dev/null || die "usbip is required; run './kindish setup'"
mapfile -t ports < <(
  usbip port 2>/dev/null | awk '
    /^Port [0-9]+:/ { port=$2; sub(/:$/, "", port) }
    /1949:9981/ { print port }
  '
)
for port in "${ports[@]}"; do
  usbip detach --port="$port"
done

VM_PID_FILE="$RUNTIME_DIR/kindish-vm.pid"
VM_DEBUG_SOCKET="$RUNTIME_DIR/kindish-debug.sock"
if pid_alive "$VM_PID_FILE" && [[ -S "$VM_DEBUG_SOCKET" ]]; then
  {
    sleep 0.2
    printf '%s\n' \
      '' \
      'initctl stop kindish-mtp-usbip 2>/dev/null || true' \
      'rmmod dummy_hcd 2>/dev/null || true'
    sleep 1
  } | socat - "UNIX-CONNECT:$VM_DEBUG_SOCKET" >/dev/null 2>&1 || true
fi
printf 'Kindle MTP detached. VM storage was preserved.\n'
