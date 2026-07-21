#!/bin/sh
set -eu

# Hardware adapter for the OTA's tizen-mtp responder. The physical script
# creates a gadget on the MT8110 UDC; Kindish creates the same FunctionFS
# layout on dummy_hcd before starting the responder.
gadget_dir="${KINDISH_MTP_GADGET_DIR:-/sys/kernel/config/usb_gadget/mtpgadget}"
udc_name="${KINDISH_MTP_UDC:-dummy_udc.0}"
ffs_dir=/dev/usb-ffs/mtp
printf '%s command=%s arg=%s gadget=%s udc=%s\n' \
  "$(date +%s)" "${1:-}" "${2:-}" "$gadget_dir" "$udc_name" \
  >>/var/log/kindish-mtp-hw.log

case "${1:-}" in
  start)
    [ -e "$gadget_dir/UDC" ]
    ;;
  mount)
    # The host mounts FunctionFS first so it can safely wait for descriptors.
    mountpoint -q "$ffs_dir"
    ;;
  umount)
    mountpoint -q "$ffs_dir" && umount "$ffs_dir" || true
    ;;
  udc)
    [ -e "$gadget_dir/UDC" ] || exit 1
    if [ "${2:-}" = enable ]; then
      current="$(cat "$gadget_dir/UDC" 2>/dev/null || true)"
      [ "$current" = "$udc_name" ] || printf '%s\n' "$udc_name" > "$gadget_dir/UDC"
    else
      printf '\n' > "$gadget_dir/UDC"
    fi
    ;;
  notify)
    if [ "${2:-}" = configured ]; then
      /usr/bin/lipc-send-event -r 3 com.lab126.hal usbConfigured 2>/dev/null || true
    else
      /usr/bin/lipc-send-event -r 3 com.lab126.hal usbUnconfigured 2>/dev/null || true
    fi
    ;;
  *)
    printf 'kindish mtp hardware adapter: unsupported command %s\n' "${1:-}" >&2
    exit 1
    ;;
esac
