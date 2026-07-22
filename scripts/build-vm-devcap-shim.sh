#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

SOURCE="$PROJECT_ROOT/vm/kindish_devcap.c"
REAL_STUB_SOURCE="$PROJECT_ROOT/vm/kindish_devcap_real_stub.c"
REAL_STUB="$CACHE_DIR/build/libkindle-cap.so.1"
OUTPUT="$CACHE_DIR/build/libdevice-cap-kindish.so.1.0"

command -v arm-linux-gnueabihf-gcc >/dev/null || \
  die "arm-linux-gnueabihf-gcc is required to build the device-capability shim"
mkdir -p "$CACHE_DIR/build"

if [[ ! -f "$REAL_STUB" || "$REAL_STUB_SOURCE" -nt "$REAL_STUB" ]]; then
  arm-linux-gnueabihf-gcc \
    -shared -fPIC -Os -Wall -Wextra -Werror \
    -Wl,-soname,libkindle-cap.so.1 \
    -o "$REAL_STUB" "$REAL_STUB_SOURCE"
fi
if [[ ! -f "$OUTPUT" || "$SOURCE" -nt "$OUTPUT" || "$REAL_STUB" -nt "$OUTPUT" ]]; then
  arm-linux-gnueabihf-gcc \
    -shared -fPIC -Os -Wall -Wextra -Werror \
    -Wl,-soname,libdevice-cap.so.1 \
    -Wl,--no-as-needed -L"$CACHE_DIR/build" -l:libkindle-cap.so.1 \
    -o "$OUTPUT" "$SOURCE" -ldl
fi
printf '%s\n' "$OUTPUT"
