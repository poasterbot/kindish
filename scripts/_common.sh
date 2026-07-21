#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="${KINDISH_CACHE_DIR:-$PROJECT_ROOT/.cache}"
FIRMWARE_VERSION="5.19.2"
FIRMWARE_NAME="update_kindle_11th_2024_${FIRMWARE_VERSION}.bin"
FIRMWARE_URL="https://s3.amazonaws.com/firmwaredownloads/$FIRMWARE_NAME"
FIRMWARE_SHA256="95826a3fd2a7ba5d3368e9a81aec132dc973650576d71c24f6773719497152e2"
FIRMWARE_FILE="$CACHE_DIR/firmware/$FIRMWARE_NAME"
EXTRACT_DIR="$CACHE_DIR/extracted/$FIRMWARE_VERSION"
ROOTFS_IMAGE="$EXTRACT_DIR/rootfs.img"
LOWER_DIR="$CACHE_DIR/rootfs"
RUNTIME_DIR="$CACHE_DIR/runtime"
ROOT_DIR="$RUNTIME_DIR/root"
RUNTIME_IMAGE="$RUNTIME_DIR/kindleos-${FIRMWARE_VERSION}-rw.img"
USERSTORE_DIR="$CACHE_DIR/userstore"
DISPLAY_NUMBER="${KINDISH_DISPLAY_NUMBER:-0}"
DISPLAY_RESOLUTION="${KINDISH_DISPLAY_RESOLUTION:-1072x1448}"
VNC_PORT="${KINDISH_VNC_PORT:-5906}"
NOVNC_PORT="${KINDISH_NOVNC_PORT:-6080}"
DISPLAY_VALUE=":$DISPLAY_NUMBER"
PID_DIR="$RUNTIME_DIR/pids"
LOG_DIR="$RUNTIME_DIR/logs"
VNC_SOCKET="$RUNTIME_DIR/kindish-vnc.sock"
PATCHED_HBC="$CACHE_DIR/patches/KPPMainApp.js.hbc.patched"

die() {
  printf 'kindish: %s\n' "$*" >&2
  exit 1
}

need_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "this command needs root (mount namespaces and loop images)"
}

is_mounted() {
  mountpoint -q "$1"
}

pid_alive() {
  [[ -s "$1" ]] && kill -0 "$(<"$1")" 2>/dev/null
}

# Host display tools must share both namespaces with OTA Xorg. The mount
# namespace exposes the guest's private X0 pathname, while the network
# namespace selects its equally private Linux abstract X0 socket.
enter_display_namespace() {
  [[ "${KINDISH_X11_ENTERED:-0}" != 1 ]] || return 0
  pid_alive "$PID_DIR/supervisor.pid" || die "KindleOS is not running"
  exec nsenter -t "$(<"$PID_DIR/supervisor.pid")" -m -n -- \
    env KINDISH_X11_ENTERED=1 DISPLAY="$DISPLAY_VALUE" "$@"
}
