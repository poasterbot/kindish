#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

kernel_release="$(uname -r)"
kernel_build="/lib/modules/$kernel_release/build"
build_dir="$CACHE_DIR/build/dummy_hcd"
source_file="$build_dir/dummy_hcd.c"
source_url="https://raw.githubusercontent.com/torvalds/linux/v6.8/drivers/usb/gadget/udc/dummy_hcd.c"
source_sha256="6892efeaca7d13e0f8ba172fac6b9607f9ac5c60de1a5f1812a57eb7998fd993"

[[ -d "$kernel_build" ]] || die "install linux-headers-$kernel_release"
mkdir -p "$build_dir"
if [[ ! -f "$source_file" ]] || ! printf '%s  %s\n' "$source_sha256" "$source_file" | sha256sum -c - >/dev/null 2>&1; then
  curl --fail --location --retry 3 "$source_url" --output "$source_file"
fi
printf '%s  %s\n' "$source_sha256" "$source_file" | sha256sum -c - >/dev/null
printf 'obj-m += dummy_hcd.o\n' >"$build_dir/Makefile"
make -s -C "$kernel_build" M="$build_dir" modules
printf '%s\n' "$build_dir/dummy_hcd.ko"
