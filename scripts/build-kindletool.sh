#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

TOOL_DIR="$CACHE_DIR/tools/KindleTool"
TOOL_BIN="$TOOL_DIR/KindleTool/Release/kindletool"
if [[ -x "$TOOL_BIN" ]]; then
  printf '%s\n' "$TOOL_BIN"
  exit 0
fi

for command in git make cc; do
  command -v "$command" >/dev/null || die "missing build command: $command"
done
mkdir -p "$(dirname "$TOOL_DIR")"
git clone --depth 1 https://github.com/KindleModding/KindleTool.git "$TOOL_DIR"
make -C "$TOOL_DIR" -j"$(nproc)"
[[ -x "$TOOL_BIN" ]] || die "KindleTool build did not produce $TOOL_BIN"
printf '%s\n' "$TOOL_BIN"
