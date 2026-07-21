#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

"$PROJECT_ROOT/scripts/fetch-firmware.sh"
KINDLETOOL="$($PROJECT_ROOT/scripts/build-kindletool.sh | tail -n 1)"
mkdir -p "$EXTRACT_DIR"

if [[ ! -f "$EXTRACT_DIR/rootfs.img.gz" ]]; then
  "$KINDLETOOL" extract "$FIRMWARE_FILE" "$EXTRACT_DIR"
fi
if [[ ! -f "$ROOTFS_IMAGE" ]]; then
  gzip --decompress --stdout "$EXTRACT_DIR/rootfs.img.gz" > "$ROOTFS_IMAGE.partial"
  mv "$ROOTFS_IMAGE.partial" "$ROOTFS_IMAGE"
fi

[[ "$(blkid -o value -s TYPE "$ROOTFS_IMAGE")" == ext3 ]] || die "extracted rootfs is not ext3"
mkdir -p "$EXTRACT_DIR/data"
if [[ ! -f "$EXTRACT_DIR/data/voice/english/lang_en_us.dat" ]]; then
  "$KINDLETOOL" extract "$EXTRACT_DIR/data.stgz" "$EXTRACT_DIR/data"
fi

printf 'Extracted official KindleOS %s rootfs: %s\n' "$FIRMWARE_VERSION" "$ROOTFS_IMAGE"
