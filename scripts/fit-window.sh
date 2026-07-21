#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

enter_display_namespace "$0" "$@"
export DISPLAY="$DISPLAY_VALUE"
deadline=$((SECONDS + 240))
window=""
while (( SECONDS < deadline )); do
  window="$(xdotool search --name 'ID:com\.lab126\.booklet\.home_' 2>/dev/null | tail -n 1 || true)"
  top="$(xdotool search --onlyvisible --name 'A:kppTopChrome_' 2>/dev/null | head -n 1 || true)"
  bottom="$(xdotool search --onlyvisible --name 'A:kppBottomChrome' 2>/dev/null | head -n 1 || true)"
  [[ -n "$window" && -n "$top" && -n "$bottom" ]] && break
  sleep 0.25
done
[[ -n "$window" && -n "${top:-}" && -n "${bottom:-}" ]] || \
  die "Kindle Home and KPP chrome did not create X11 windows (see $LOG_DIR/kindleos.log)"

"$PROJECT_ROOT/scripts/window-manager.sh" --once
printf 'Kindle Home and native KPP navigation chrome fitted to %s.\n' "$DISPLAY_RESOLUTION"
