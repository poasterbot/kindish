#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

if [[ -d "$ROOT_DIR" ]]; then
  mapfile -t mounts < <(findmnt -rn -o TARGET | awk -v root="$ROOT_DIR" 'index($0, root) == 1 { print length, $0 }' | sort -rn | cut -d' ' -f2-)
  for target in "${mounts[@]}"; do
    umount "$target" 2>/dev/null || umount -l "$target" 2>/dev/null || true
  done
fi
is_mounted "$LOWER_DIR" && umount "$LOWER_DIR" || true
printf 'Runtime unmounted. Persistent runtime image and userstore were kept.\n'
