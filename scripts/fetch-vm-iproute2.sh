#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

IPROUTE_VERSION="5.15.0-1ubuntu2.2"
IPROUTE_SHA256="7c5a0928c9af9f5a5d33f611a0cdfeaa9bc8b0c8cca7d66270e3e4c85b737559"
LIBBPF_VERSION="0.5.0-1"
LIBBPF_SHA256="dda31e5d525dced1bfb445b20bdd566da05028871c4bf513b993d2482ac52644"
LIBELF_VERSION="0.186-1build1"
LIBELF_SHA256="1f0d58db5d563e9c7a00d1c03b16b46a8298a39ec48fa6147163a084003fa913"
LIBMNL_VERSION="1.0.4-3build2"
LIBMNL_SHA256="e0036508645a11a22a1b02caae2d4c040c36c697c482aeb0c833eb1d061db614"
IPROUTE_ROOT="$CACHE_DIR/tools/iproute2-${IPROUTE_VERSION}-armhf"

download_package() {
  local url=$1 destination=$2 checksum=$3
  if [[ ! -f "$destination" ]]; then
    curl --fail --location --retry 3 --output "$destination.partial" "$url"
    mv "$destination.partial" "$destination"
  fi
  printf '%s  %s\n' "$checksum" "$destination" | sha256sum --check >/dev/null
}

command -v dpkg-deb >/dev/null || die "dpkg-deb is required to unpack ARM iproute2"
mkdir -p "$CACHE_DIR/tools" "$IPROUTE_ROOT"
IPROUTE_PACKAGE="$CACHE_DIR/tools/iproute2_${IPROUTE_VERSION}_armhf.deb"
LIBBPF_PACKAGE="$CACHE_DIR/tools/libbpf0_${LIBBPF_VERSION}_armhf.deb"
LIBELF_PACKAGE="$CACHE_DIR/tools/libelf1_${LIBELF_VERSION}_armhf.deb"
LIBMNL_PACKAGE="$CACHE_DIR/tools/libmnl0_${LIBMNL_VERSION}_armhf.deb"

download_package \
  "https://ports.ubuntu.com/ubuntu-ports/pool/main/i/iproute2/iproute2_${IPROUTE_VERSION}_armhf.deb" \
  "$IPROUTE_PACKAGE" "$IPROUTE_SHA256"
download_package \
  "https://ports.ubuntu.com/ubuntu-ports/pool/main/libb/libbpf/libbpf0_${LIBBPF_VERSION}_armhf.deb" \
  "$LIBBPF_PACKAGE" "$LIBBPF_SHA256"
download_package \
  "https://ports.ubuntu.com/ubuntu-ports/pool/main/e/elfutils/libelf1_${LIBELF_VERSION}_armhf.deb" \
  "$LIBELF_PACKAGE" "$LIBELF_SHA256"
download_package \
  "https://ports.ubuntu.com/ubuntu-ports/pool/main/libm/libmnl/libmnl0_${LIBMNL_VERSION}_armhf.deb" \
  "$LIBMNL_PACKAGE" "$LIBMNL_SHA256"

if [[ ! -x "$IPROUTE_ROOT/bin/ip" ]]; then
  dpkg-deb --extract "$IPROUTE_PACKAGE" "$IPROUTE_ROOT"
  dpkg-deb --extract "$LIBBPF_PACKAGE" "$IPROUTE_ROOT"
  dpkg-deb --extract "$LIBELF_PACKAGE" "$IPROUTE_ROOT"
  dpkg-deb --extract "$LIBMNL_PACKAGE" "$IPROUTE_ROOT"
fi

printf '%s\n' \
  "$IPROUTE_ROOT/bin/ip" \
  "$IPROUTE_ROOT/usr/lib/arm-linux-gnueabihf/libbpf.so.0" \
  "$IPROUTE_ROOT/usr/lib/arm-linux-gnueabihf/libelf.so.1" \
  "$IPROUTE_ROOT/usr/lib/arm-linux-gnueabihf/libmnl.so.0"
