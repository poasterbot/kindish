#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

gadget=/sys/kernel/config/usb_gadget/mtpgadget
unbind_pid=
if [[ -d "$gadget" ]]; then
  # dummy_hcd waits for FunctionFS to close while disconnecting. Start the
  # disconnect first, then stop the responder so both sides of that handshake
  # can finish without deadlocking the calling shell.
  (printf '\n' >"$gadget/UDC" 2>/dev/null || true) &
  unbind_pid=$!
fi

if pid_alive "$PID_DIR/mtp.pid"; then
  pid="$(<"$PID_DIR/mtp.pid")"
  kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
  for _ in {1..30}; do kill -0 "$pid" 2>/dev/null || break; sleep .05; done
  kill -0 "$pid" 2>/dev/null && kill -KILL -- "-$pid" 2>/dev/null || true
fi
[[ ! -e "$PID_DIR/mtp.pid" ]] || unlink "$PID_DIR/mtp.pid"

if [[ -n "$unbind_pid" ]]; then
  for _ in {1..100}; do kill -0 "$unbind_pid" 2>/dev/null || break; sleep .05; done
  kill -0 "$unbind_pid" 2>/dev/null && die "virtual UDC disconnect did not complete"
  wait "$unbind_pid" 2>/dev/null || true
fi
if [[ -d "$gadget" ]]; then
  for link in "$gadget/configs/c.1/"ffs.*; do
    [[ -L "$link" ]] && unlink "$link"
  done
fi

mountpoint -q "$ROOT_DIR/dev/usb-ffs/mtp" && umount "$ROOT_DIR/dev/usb-ffs/mtp" || true
if [[ -d "$gadget" ]]; then
  for function in "$gadget/functions/"ffs.*; do
    [[ -d "$function" ]] && rmdir "$function"
  done
  rmdir "$gadget/configs/c.1/strings/0x409" "$gadget/configs/c.1" \
    "$gadget/strings/0x409" "$gadget"
fi
printf 'Virtual Kindle MTP detached. User storage was kept.\n'
