#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

online=0
case "${1:-}" in
  --online) online=1 ;;
  '') ;;
  *) die "usage: ./kindish start [--online]" ;;
esac
for command in nsenter socat websockify x11vnc; do
  command -v "$command" >/dev/null || die "$command is required; run './kindish setup'"
done

"$PROJECT_ROOT/scripts/mount-runtime.sh" >/dev/null
mkdir -p "$PID_DIR" "$LOG_DIR"
[[ ! -e "$VNC_SOCKET" ]] || unlink "$VNC_SOCKET"
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

# A private mount namespace gives the simulated device its own canonical X11
# socket directory, so the OTA server can honestly own display :0 without
# touching a host X0. Its network namespace also isolates Xorg's abstract X0
# socket and contains only loopback unless online mode adds virtual Wi-Fi.
# IPC isolation keeps Lab126's SysV capability segment self-contained. A
# nested PID namespace is deliberately avoided because qemu-arm's translated
# futex path can deadlock there.
nohup setsid unshare --mount --net --ipc --fork \
  sh -c '
    mount --make-rprivate /
    mount -t tmpfs -o mode=1777,nosuid,nodev kindish-x11 /tmp/.X11-unix
    mount --bind /tmp/.X11-unix "$1/var/tmp/.X11-unix"
    ip link set lo up
    export KINDISH_ONLINE="$2" DISPLAY="$3"
    exec chroot "$1" /usr/local/bin/kindish-guest-init
  ' sh "$ROOT_DIR" "$online" "$DISPLAY_VALUE" \
  >"$LOG_DIR/kindleos.log" 2>&1 </dev/null &
printf '%s\n' "$!" > "$PID_DIR/supervisor.pid"
supervisor_pid="$(<"$PID_DIR/supervisor.pid")"

if [[ "$online" -eq 1 ]]; then
  if ! "$PROJECT_ROOT/scripts/network-online-start.sh" "$supervisor_pid"; then
    "$PROJECT_ROOT/scripts/stop.sh" >/dev/null
    exit 1
  fi
fi

# Xorg itself is the ARM binary and mtk_drv.so from the OTA. It starts inside
# the guest supervisor above, so it shares the offline network and IPC
# namespaces with the rest of KindleOS.
for _ in {1..600}; do
  nsenter -t "$supervisor_pid" -m -- \
    test -S "/tmp/.X11-unix/X$DISPLAY_NUMBER" 2>/dev/null && break
  pid_alive "$PID_DIR/supervisor.pid" || die "KindleOS supervisor exited while starting OTA Xorg"
  sleep 0.05
done
nsenter -t "$supervisor_pid" -m -- \
  test -S "/tmp/.X11-unix/X$DISPLAY_NUMBER" || die "OTA Xorg failed to start"

# Share Kindle's private X11 mount, but give the framebuffer reader a second,
# empty network namespace. libX11 therefore falls back from an unreachable
# abstract X0 to the correct private pathname X0, while x11vnc cannot expose a
# listener through either the host or Kindle's simulated Wi-Fi interface.
nohup setsid nsenter -t "$supervisor_pid" -m -- unshare --net --fork \
  sh -c 'ip link set lo up; exec "$@"' sh \
  x11vnc -display "$DISPLAY_VALUE" -noshm -forever -shared -nopw \
    -rfbport 0 -unixsock "$VNC_SOCKET" \
  >"$LOG_DIR/x11vnc.log" 2>&1 </dev/null &
printf '%s\n' "$!" > "$PID_DIR/x11vnc.pid"
for _ in {1..200}; do
  [[ -S "$VNC_SOCKET" ]] && break
  pid_alive "$PID_DIR/x11vnc.pid" || die "x11vnc failed to attach to private display $DISPLAY_VALUE"
  sleep 0.05
done
[[ -S "$VNC_SOCKET" ]] || die "x11vnc did not create its local transport socket"

nohup setsid socat \
  "TCP4-LISTEN:$VNC_PORT,bind=127.0.0.1,reuseaddr,fork" \
  "UNIX-CONNECT:$VNC_SOCKET" \
  >"$LOG_DIR/vnc-bridge.log" 2>&1 </dev/null &
printf '%s\n' "$!" > "$PID_DIR/vnc-bridge.pid"

nohup setsid websockify --web=/usr/share/novnc/ --wrap-mode=ignore \
  --unix-target="$VNC_SOCKET" "127.0.0.1:$NOVNC_PORT" \
  >"$LOG_DIR/novnc.log" 2>&1 </dev/null &
printf '%s\n' "$!" > "$PID_DIR/novnc.pid"

if [[ "$online" -eq 1 ]]; then
  if ! "$PROJECT_ROOT/scripts/wait-online-window.sh"; then
    "$PROJECT_ROOT/scripts/stop.sh" >/dev/null
    exit 1
  fi
else
  if ! "$PROJECT_ROOT/scripts/fit-window.sh"; then
    "$PROJECT_ROOT/scripts/stop.sh" >/dev/null
    exit 1
  fi

  nohup setsid "$PROJECT_ROOT/scripts/window-manager.sh" \
    >"$LOG_DIR/window-manager.log" 2>&1 </dev/null &
  printf '%s\n' "$!" > "$PID_DIR/window-manager.pid"
fi

printf 'KindleOS 5.19.2 is running.\n'
printf '  Browser: http://127.0.0.1:%s/vnc.html?autoconnect=1&resize=scale\n' "$NOVNC_PORT"
printf '  VNC:     127.0.0.1:%s\n' "$VNC_PORT"
printf '  Display: private Kindle X server on %s\n' "$DISPLAY_VALUE"
printf '  Logs:    %s\n' "$LOG_DIR"
if [[ "$online" -eq 1 ]]; then
  printf '  Network: online through isolated virtual Wi-Fi\n'
else
  printf '  Network: offline (isolated namespace)\n'
fi
