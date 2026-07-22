#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

mkdir -p "$(dirname "$FIRMWARE_FILE")"
if [[ -f "$FIRMWARE_FILE" ]] && echo "$FIRMWARE_SHA256  $FIRMWARE_FILE" | sha256sum --check --status; then
  printf 'Firmware already verified: %s\n' "$FIRMWARE_FILE"
  exit 0
fi

printf 'Downloading the official KT6 %s recovery OTA from Amazon...\n' "$FIRMWARE_VERSION"
curl --fail --location --retry 3 --continue-at - --output "$FIRMWARE_FILE" "$FIRMWARE_URL"
echo "$FIRMWARE_SHA256  $FIRMWARE_FILE" | sha256sum --check --status || die "firmware checksum mismatch"
printf 'Verified: %s\n' "$FIRMWARE_FILE"
