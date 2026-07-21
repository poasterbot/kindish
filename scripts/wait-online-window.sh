#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

enter_display_namespace "$0" "$@"
export DISPLAY="$DISPLAY_VALUE"
deadline=$((SECONDS + 240))
window=""
while (( SECONDS < deadline )); do
  window="$(xdotool search --onlyvisible --name 'ID:com\.lab126\.oobe_' \
    2>/dev/null | tail -n 1 || true)"
  if [[ -n "$window" ]]; then
    width="$(xdotool getwindowgeometry --shell "$window" 2>/dev/null | \
      sed -n 's/^WIDTH=//p')"
    [[ "${width:-0}" -gt 100 ]] && break
  fi
  sleep 0.25
done
[[ -n "$window" && "${width:-0}" -gt 100 ]] || \
  die "Kindle account setup did not create its X11 window (see $ROOT_DIR/var/log/messages)"

deadline=$((SECONDS + 90))
while (( SECONDS < deadline )); do
  if chroot "$ROOT_DIR" /usr/bin/lipc-get-prop com.lab126.wifid cmState \
      2>/dev/null | grep -q '^CONNECTED$' &&
      ip -4 address show dev wlan0 2>/dev/null | grep -q 'inet '; then
    break
  fi
  sleep 0.25
done
chroot "$ROOT_DIR" /usr/bin/lipc-get-prop com.lab126.wifid cmState \
  2>/dev/null | grep -q '^CONNECTED$' || \
  die "Kindle wifid did not connect to the virtual adapter"
chroot "$ROOT_DIR" /usr/bin/curl --fail --silent --show-error --max-time 15 \
  https://example.com/ >/dev/null || die "KindleOS Internet validation failed"
printf 'Kindle account setup screen is ready.\n'
