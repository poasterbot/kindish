#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

TOOLS_VERSION="5.15.0-73.80"
TOOLS_SHA256="a25b337e0d5d93b19e5cfd270167658b814293918c00e96362032b750c1d2714"
TOOLS_PACKAGE="$CACHE_DIR/tools/linux-tools-5.15.0-73_${TOOLS_VERSION}_armhf.deb"
UDEV_VERSION="249.11-0ubuntu3.21"
UDEV_SHA256="8da1a64a4d93cd1cf496f4d1a82506245382c8e9d571b7cb7c289261f0a16ddf"
UDEV_PACKAGE="$CACHE_DIR/tools/libudev1_${UDEV_VERSION}_armhf.deb"
USBIP_ROOT="$CACHE_DIR/tools/usbip-${TOOLS_VERSION}-armhf"

download_package() {
  local url=$1 destination=$2 checksum=$3
  if [[ ! -f "$destination" ]]; then
    curl --fail --location --retry 3 --output "$destination.partial" "$url"
    mv "$destination.partial" "$destination"
  fi
  printf '%s  %s\n' "$checksum" "$destination" | sha256sum --check >/dev/null
}

command -v dpkg-deb >/dev/null || die "dpkg-deb is required to unpack ARM USB/IP"
mkdir -p "$CACHE_DIR/tools"
download_package \
  "https://ports.ubuntu.com/ubuntu-ports/pool/main/l/linux/linux-tools-5.15.0-73_${TOOLS_VERSION}_armhf.deb" \
  "$TOOLS_PACKAGE" "$TOOLS_SHA256"
download_package \
  "https://ports.ubuntu.com/ubuntu-ports/pool/main/s/systemd/libudev1_${UDEV_VERSION}_armhf.deb" \
  "$UDEV_PACKAGE" "$UDEV_SHA256"

if [[ ! -x "$USBIP_ROOT/usr/lib/linux-tools-5.15.0-73/usbipd" ]]; then
  mkdir -p "$USBIP_ROOT"
  dpkg-deb --extract "$TOOLS_PACKAGE" "$USBIP_ROOT"
  dpkg-deb --extract "$UDEV_PACKAGE" "$USBIP_ROOT"
fi

printf '%s\n' \
  "$USBIP_ROOT/usr/lib/linux-tools-5.15.0-73/usbip" \
  "$USBIP_ROOT/usr/lib/linux-tools-5.15.0-73/usbipd" \
  "$USBIP_ROOT/usr/lib/arm-linux-gnueabihf/libudev.so.1"
