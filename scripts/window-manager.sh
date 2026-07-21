#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

enter_display_namespace "$0" "$@"
export DISPLAY="$DISPLAY_VALUE"

width="${DISPLAY_RESOLUTION%x*}"
height="${DISPLAY_RESOLUTION#*x}"
top_height="${KINDISH_TOP_CHROME_HEIGHT:-115}"
bottom_height="${KINDISH_BOTTOM_CHROME_HEIGHT:-162}"
content_height=$((height - top_height - bottom_height))
bottom_y=$((height - bottom_height))

find_window() {
  xdotool search --onlyvisible --name "$1" 2>/dev/null | head -n 1 || true
}

find_active_app() {
  # xwininfo reports root children from top to bottom. The first mapped L:A_
  # surface is therefore the booklet KPP most recently activated; unlike a
  # resource-ID heuristic this correctly follows Home/Library/Back transitions.
  xwininfo -root -tree 2>/dev/null |
    sed -n 's/^[[:space:]]*\(0x[0-9a-fA-F]*\) "L:A_.*/\1/p' |
    head -n 1 || true
}

layout_once() {
  local active top bottom
  active="$(find_active_app)"
  top="$(find_window 'A:kppTopChrome_')"
  bottom="$(find_window 'A:kppBottomChrome')"

  [[ -n "$active" && -n "$top" && -n "$bottom" ]] || return 1

  # Preserve KindleOS's real KPP chrome and give only the middle region to the
  # active booklet. Raising in this order leaves both chrome surfaces above it.
  xdotool windowmap "$active"
  xdotool windowmove "$active" 0 "$top_height"
  xdotool windowsize "$active" "$width" "$content_height"
  xdotool windowraise "$active"

  xdotool windowmap "$bottom"
  xdotool windowmove "$bottom" 0 "$bottom_y"
  xdotool windowsize "$bottom" "$width" "$bottom_height"
  xdotool windowraise "$bottom"

  xdotool windowmap "$top"
  xdotool windowmove "$top" 0 0
  xdotool windowsize "$top" "$width" "$top_height"
  xdotool windowraise "$top"

  printf '%s\n' "$active" > "$RUNTIME_DIR/window.id"
  printf '%s:%s:%s\n' "$active" "$top" "$bottom"
}

if [[ "${1:-}" == "--once" ]]; then
  layout_once >/dev/null
  exit
fi

# There is intentionally no desktop window manager in the guest: the one from
# the physical device applies MT8110 rotation assumptions. Watch for booklet
# changes and apply the native portrait layout only when the active set changes.
last_layout=""
while true; do
  active="$(find_active_app)"
  top="$(find_window 'A:kppTopChrome_')"
  bottom="$(find_window 'A:kppBottomChrome')"
  signature="$active:$top:$bottom"
  if [[ -n "$active" && -n "$top" && -n "$bottom" && "$signature" != "$last_layout" ]]; then
    if current="$(layout_once 2>/dev/null)"; then
      printf 'laid out %s at %(%FT%TZ)T\n' "$current" -1
      last_layout="$current"
    fi
  fi
  sleep 0.5
done
