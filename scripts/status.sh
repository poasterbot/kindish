#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

if pid_alive "$PID_DIR/supervisor.pid"; then
  printf 'running (PID %s), noVNC http://127.0.0.1:%s/vnc.html?autoconnect=1&resize=scale\n' \
    "$(<"$PID_DIR/supervisor.pid")" "$NOVNC_PORT"
  if pid_alive "$PID_DIR/mtp.pid" && lsusb -d 1949:9981 >/dev/null 2>&1; then
    printf 'MTP attached (Amazon 1949:9981)\n'
  else
    printf 'MTP detached\n'
  fi
else
  printf 'stopped\n'
  exit 1
fi
