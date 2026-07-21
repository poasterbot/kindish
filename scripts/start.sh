#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

"$PROJECT_ROOT/scripts/mount-runtime.sh" >/dev/null
mkdir -p "$PID_DIR" "$LOG_DIR" /tmp/.X11-unix
: > "$ROOT_DIR/var/log/kindish-services.log"
: > "$ROOT_DIR/var/log/kindish-kpp.log"

if pid_alive "$PID_DIR/supervisor.pid"; then
  die "already running (PID $(<"$PID_DIR/supervisor.pid"))"
fi

# Model the KT6 absolute touch panel with a real Linux input device. Xorg opens
# it through the OTA's multitouch module; no application-level click mapping is
# involved.
modprobe uinput
nohup setsid "$CACHE_DIR/build/kindish-uinput" >"$LOG_DIR/uinput.log" 2>&1 </dev/null &
printf '%s\n' "$!" > "$PID_DIR/touch.pid"
touch_event=""
for _ in {1..100}; do
  for name_file in /sys/class/input/event*/device/name; do
    [[ -r "$name_file" ]] || continue
    if [[ "$(<"$name_file")" == kindish-zforce ]]; then
      touch_event="/dev/input/$(basename "$(dirname "$(dirname "$name_file")")")"
      break 2
    fi
  done
  sleep 0.05
done
[[ -n "$touch_event" && -e "$touch_event" ]] || die "virtual touch device failed to start"
read -r touch_major_hex touch_minor_hex < <(stat -c '%t %T' "$touch_event")
touch_node="$ROOT_DIR/dev/input/kindish-touch"
[[ ! -e "$touch_node" ]] || unlink "$touch_node"
mknod -m 0666 "$touch_node" c "$((16#$touch_major_hex))" "$((16#$touch_minor_hex))"

install -D -m 0755 "$PROJECT_ROOT/guest/kindish-guest-init.sh" \
  "$ROOT_DIR/usr/local/bin/kindish-guest-init"

# A new network namespace contains only loopback: KindleOS cannot reach the
# host or Internet. Loopback is brought up because several Lab126 clients use
# local TCP health probes. IPC isolation keeps Lab126's SysV
# capability segment self-contained. A nested PID namespace is deliberately
# avoided because qemu-arm's translated futex path can deadlock there.
nohup setsid unshare --net --ipc --fork \
  sh -c 'ip link set lo up; exec chroot "$1" /usr/local/bin/kindish-guest-init' sh "$ROOT_DIR" \
  >"$LOG_DIR/kindleos.log" 2>&1 </dev/null &
printf '%s\n' "$!" > "$PID_DIR/supervisor.pid"

# Xorg itself is the ARM binary and mtk_drv.so from the OTA. It starts inside
# the guest supervisor above, so it shares the offline network and IPC
# namespaces with the rest of KindleOS.
for _ in {1..600}; do
  [[ -S "/tmp/.X11-unix/X$DISPLAY_NUMBER" ]] && break
  pid_alive "$PID_DIR/supervisor.pid" || die "KindleOS supervisor exited while starting OTA Xorg"
  sleep 0.05
done
[[ -S "/tmp/.X11-unix/X$DISPLAY_NUMBER" ]] || die "OTA Xorg failed to start"

nohup setsid x11vnc -display "$DISPLAY_VALUE" -noshm -localhost -forever -shared -nopw \
  -rfbport "$VNC_PORT" >"$LOG_DIR/x11vnc.log" 2>&1 </dev/null &
printf '%s\n' "$!" > "$PID_DIR/x11vnc.pid"

nohup setsid websockify --web=/usr/share/novnc/ --wrap-mode=ignore \
  "127.0.0.1:$NOVNC_PORT" "127.0.0.1:$VNC_PORT" \
  >"$LOG_DIR/novnc.log" 2>&1 </dev/null &
printf '%s\n' "$!" > "$PID_DIR/novnc.pid"

if ! "$PROJECT_ROOT/scripts/fit-window.sh"; then
  "$PROJECT_ROOT/scripts/stop.sh" >/dev/null
  exit 1
fi

nohup setsid "$PROJECT_ROOT/scripts/window-manager.sh" \
  >"$LOG_DIR/window-manager.log" 2>&1 </dev/null &
printf '%s\n' "$!" > "$PID_DIR/window-manager.pid"

printf 'KindleOS 5.19.2 is running.\n'
printf '  Browser: http://127.0.0.1:%s/vnc.html?autoconnect=1&resize=scale\n' "$NOVNC_PORT"
printf '  VNC:     127.0.0.1:%s\n' "$VNC_PORT"
printf '  Logs:    %s\n' "$LOG_DIR"
