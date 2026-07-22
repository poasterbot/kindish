#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

VM_PID_FILE="$RUNTIME_DIR/kindish-vm.pid"
if ! pid_alive "$VM_PID_FILE"; then
  printf 'stopped\n'
  exit 1
fi

printf 'running (PID %s)\n' "$(<"$VM_PID_FILE")"
printf 'Browser http://127.0.0.1:%s/vnc.html?autoconnect=1&resize=scale\n' "$NOVNC_PORT"
printf 'VNC 127.0.0.1:%s; SSH 127.0.0.1:10022\n' "$VNC_PORT"
if [[ -S "$RUNTIME_DIR/kindish-debug.sock" ]]; then
  printf 'Amazon /sbin/init diagnostic console ready\n'
fi
if lsusb -d 1949:9981 >/dev/null 2>&1; then
  printf 'MTP attached (Amazon 1949:9981)\n'
else
  printf 'MTP available in the VM; run ./kindish mtp-start to attach it\n'
fi
