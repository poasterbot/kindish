#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

pid_alive "$PID_DIR/supervisor.pid" || die "start KindleOS before enabling MTP"
[[ -d "$ROOT_DIR/dev/usb-ffs" ]] || die "runtime device tree is not mounted"

modprobe libcomposite
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
if [[ ! -e /sys/class/udc/dummy_udc.0 ]]; then
  if ! modprobe dummy_hcd 2>/dev/null; then
    module="$($PROJECT_ROOT/scripts/build-dummy-hcd.sh)"
    insmod "$module"
  fi
fi
[[ -e /sys/class/udc/dummy_udc.0 ]] || die "dummy_hcd did not create dummy_udc.0"

gadget=/sys/kernel/config/usb_gadget/mtpgadget
function_name=kindish-mtp
[[ ! -e "$gadget" ]] || die "the Kindish MTP gadget already exists; run 'kindish mtp-stop' first"
mkdir -p "$gadget/strings/0x409" "$gadget/configs/c.1/strings/0x409"
printf '0x1949\n' >"$gadget/idVendor"
printf '0x9981\n' >"$gadget/idProduct"
printf '0x0200\n' >"$gadget/bcdUSB"
printf '0x0223\n' >"$gadget/bcdDevice"
printf 'B0D4KINDISHKT6001\n' >"$gadget/strings/0x409/serialnumber"
printf 'Amazon\n' >"$gadget/strings/0x409/manufacturer"
printf 'Kindle B0D4KINDISHKT6001\n' >"$gadget/strings/0x409/product"
printf 'MTP\n' >"$gadget/configs/c.1/strings/0x409/configuration"
printf '0xc0\n' >"$gadget/configs/c.1/bmAttributes"
printf '500\n' >"$gadget/configs/c.1/MaxPower"
mkdir "$gadget/functions/ffs.$function_name"

mkdir -p "$ROOT_DIR/dev/usb-ffs/mtp"
mountpoint -q "$ROOT_DIR/dev/usb-ffs/mtp" || \
  mount -t functionfs -o uid=0,gid=0 "$function_name" "$ROOT_DIR/dev/usb-ffs/mtp"

supervisor="$(<"$PID_DIR/supervisor.pid")"
nohup setsid nsenter -t "$supervisor" -n -i -- \
  chroot "$ROOT_DIR" /usr/bin/env QEMU_CPU=cortex-a7 \
  LD_PRELOAD=/usr/local/lib/libkindish-shim.so /usr/bin/tizen-mtp -f \
  >"$LOG_DIR/mtp.log" 2>&1 </dev/null &
mtp_pid="$!"
printf '%s\n' "$mtp_pid" >"$PID_DIR/mtp.pid"

# FunctionFS will reject linking until Amazon's responder has published its
# descriptors. The OTA mtp.sh adapter binds dummy_udc after startMtp.
linked=0
for _ in {1..200}; do
  if ln -s "$gadget/functions/ffs.$function_name" \
      "$gadget/configs/c.1/ffs.$function_name" 2>/dev/null; then
    linked=1
    break
  fi
  pid_alive "$PID_DIR/mtp.pid" || die "Amazon tizen-mtp exited (see $LOG_DIR/mtp.log)"
  sleep .05
done
[[ "$linked" -eq 1 ]] || die "tizen-mtp did not publish its FunctionFS descriptors"

guest() {
  nsenter -t "$supervisor" -n -i -- chroot "$ROOT_DIR" "$@"
}
# On physical hardware volumd emits this after the MT8110 drive-mode IRQ and
# unmounts /mnt/us. Kindish keeps its shared userstore mounted and synthesizes
# only that hardware-completion edge; the responder and protocol remain OTA.
state_two=0
sleep .5
for _ in {1..60}; do
  guest /usr/bin/lipc-set-prop -q -- com.lab126.mtp startMtp 1 >/dev/null 2>&1 || true
  sleep .2
  if tail -n 250 "$ROOT_DIR/var/log/messages" 2>/dev/null | \
      rg -q "mtp-responder\\[$mtp_pid\\].*handled state_change_event \\[12\\].*current mtp state"; then
    state_two=1
    break
  fi
  pid_alive "$PID_DIR/mtp.pid" || die "Amazon tizen-mtp exited (see $LOG_DIR/mtp.log)"
done
[[ "$state_two" -eq 1 ]] || die "tizen-mtp did not reach its configured state"
guest /usr/bin/lipc-send-event -r 3 com.lab126.volumd driveModeStateChanged -i 1

for _ in {1..100}; do
  lsusb -d 1949:9981 >/dev/null 2>&1 && break
  sleep .05
done
lsusb -d 1949:9981 >/dev/null 2>&1 || die "virtual Kindle did not enumerate"
printf 'Virtual Kindle MTP attached (Amazon 1949:9981). User storage: %s\n' "$USERSTORE_DIR"
