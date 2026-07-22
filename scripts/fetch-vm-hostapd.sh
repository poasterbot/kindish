#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

HOSTAPD_VERSION="2.10-6ubuntu2.4"
HOSTAPD_SHA256="3042cbacffa6ed3d3ef3eda1aaa786356147b2bbe73e686c98aba1f08e581654"
HOSTAPD_PACKAGE="$CACHE_DIR/tools/hostapd_${HOSTAPD_VERSION}_armhf.deb"
HOSTAPD_ROOT="$CACHE_DIR/tools/hostapd-${HOSTAPD_VERSION}-armhf"
HOSTAPD_BINARY="$HOSTAPD_ROOT/usr/sbin/hostapd"

command -v dpkg-deb >/dev/null || die "dpkg-deb is required to unpack ARM hostapd"
mkdir -p "$CACHE_DIR/tools"
if [[ ! -f "$HOSTAPD_PACKAGE" ]]; then
  curl --fail --location --retry 3 \
    --output "$HOSTAPD_PACKAGE.partial" \
    "https://ports.ubuntu.com/ubuntu-ports/pool/universe/w/wpa/hostapd_${HOSTAPD_VERSION}_armhf.deb"
  mv "$HOSTAPD_PACKAGE.partial" "$HOSTAPD_PACKAGE"
fi
printf '%s  %s\n' "$HOSTAPD_SHA256" "$HOSTAPD_PACKAGE" | sha256sum --check >/dev/null
if [[ ! -x "$HOSTAPD_BINARY" ]]; then
  mkdir -p "$HOSTAPD_ROOT"
  dpkg-deb --extract "$HOSTAPD_PACKAGE" "$HOSTAPD_ROOT"
fi
printf '%s\n' "$HOSTAPD_BINARY"
