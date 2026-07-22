#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

SOURCE="$PROJECT_ROOT/vm/kindish-power-button.c"
OUTPUT="$CACHE_DIR/build/kindish-power-button"

command -v arm-linux-gnueabihf-gcc >/dev/null || \
  die "arm-linux-gnueabihf-gcc is required to build the power-button bridge"
mkdir -p "$CACHE_DIR/build"

if [[ ! -f "$OUTPUT" || "$SOURCE" -nt "$OUTPUT" ]]; then
  arm-linux-gnueabihf-gcc \
    -static -Os -Wall -Wextra -Werror \
    -o "$OUTPUT" "$SOURCE"
fi
printf '%s\n' "$OUTPUT"
