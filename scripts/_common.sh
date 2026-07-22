#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="${KINDISH_CACHE_DIR:-$PROJECT_ROOT/.cache}"
FIRMWARE_VERSION="5.18.5.0.1"
FIRMWARE_NAME="update_kindle_11th_2024_${FIRMWARE_VERSION}.bin"
FIRMWARE_URL="https://s3.amazonaws.com/firmwaredownloads/$FIRMWARE_NAME"
FIRMWARE_SHA256="7cbd3e7e4fb54d67d2b3b13f2b0e2b63dabc09bcac6164271653c21d5426a8d3"
FIRMWARE_FILE="$CACHE_DIR/firmware/$FIRMWARE_NAME"
EXTRACT_DIR="$CACHE_DIR/extracted/$FIRMWARE_VERSION"
ROOTFS_IMAGE="$EXTRACT_DIR/rootfs.img"
LOWER_DIR="$CACHE_DIR/rootfs"
RUNTIME_DIR="$CACHE_DIR/runtime"
VNC_PORT="${KINDISH_VNC_PORT:-5906}"
NOVNC_PORT="${KINDISH_NOVNC_PORT:-6080}"
PID_DIR="$RUNTIME_DIR/pids"
LOG_DIR="$RUNTIME_DIR/logs"

die() {
  printf 'kindish: %s\n' "$*" >&2
  exit 1
}

need_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "this command needs root (loop images and USB/IP)"
}

is_mounted() {
  mountpoint -q "$1"
}

pid_alive() {
  [[ -s "$1" ]] && kill -0 "$(<"$1")" 2>/dev/null
}
