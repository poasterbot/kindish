#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

"$PROJECT_ROOT/scripts/mtp-stop.sh" >/dev/null 2>&1 || true
"$PROJECT_ROOT/scripts/network-online-stop.sh" >/dev/null 2>&1 || true

for name in window-manager supervisor novnc vnc-bridge x11vnc touch; do
  pid_file="$PID_DIR/$name.pid"
  if pid_alive "$pid_file"; then
    # Each top-level service is its own session/process group. Terminating the
    # group also catches daemon forks and the qemu-arm translated children.
    kill -- "-$(<"$pid_file")" 2>/dev/null || kill "$(<"$pid_file")" 2>/dev/null || true
  fi
done
sleep 0.5
for name in window-manager supervisor novnc vnc-bridge x11vnc touch; do
  pid_file="$PID_DIR/$name.pid"
  if pid_alive "$pid_file"; then
    kill -KILL -- "-$(<"$pid_file")" 2>/dev/null || kill -KILL "$(<"$pid_file")" 2>/dev/null || true
  fi
  [[ ! -e "$pid_file" ]] || unlink "$pid_file"
done
[[ ! -e "$VNC_SOCKET" ]] || unlink "$VNC_SOCKET"
"$PROJECT_ROOT/scripts/unmount-runtime.sh" >/dev/null
printf 'KindleOS stopped. The writable runtime and user storage were kept.\n'
