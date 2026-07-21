#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
"$PROJECT_ROOT/scripts/extract-firmware.sh" >/dev/null

KINDLETOOL="$($PROJECT_ROOT/scripts/build-kindletool.sh | tail -n 1)"
"$KINDLETOOL" convert -i "$FIRMWARE_FILE"
printf '\nBoot FIT:\n'
dumpimage -l "$EXTRACT_DIR/mt8110_bellatrix/boot.img"
printf '\nRoot filesystem:\n'
file "$ROOTFS_IMAGE"
printf 'Version: '
sed -n '1p' "$LOWER_DIR/etc/version.txt" 2>/dev/null || printf '%s (mount runtime for full metadata)\n' "$FIRMWARE_VERSION"
