#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

command -v arm-linux-gnueabihf-gcc >/dev/null || die "install gcc-arm-linux-gnueabihf"
mkdir -p "$CACHE_DIR/build"
arm-linux-gnueabihf-gcc -U_FILE_OFFSET_BITS -D_FILE_OFFSET_BITS=32 -U_TIME_BITS -D_TIME_BITS=32 \
  -shared -fPIC -O2 -Wall -Wextra \
  -o "$CACHE_DIR/build/libkindish-shim.so" "$PROJECT_ROOT/src/kindish_shim.c" -ldl
gcc -O2 -Wall -Wextra -o "$CACHE_DIR/build/kindish-uinput" \
  "$PROJECT_ROOT/src/kindish_uinput.c"
file "$CACHE_DIR/build/libkindish-shim.so"
