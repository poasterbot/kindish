#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

VM_PID_FILE="$RUNTIME_DIR/kindish-vm.pid"
VM_DEBUG_SOCKET="$RUNTIME_DIR/kindish-debug.sock"
pid_alive "$VM_PID_FILE" || die "start the Kindle VM before attaching MTP"
[[ -S "$VM_DEBUG_SOCKET" ]] || die "the Kindle VM diagnostic console is unavailable"
for command in lsusb socat usbip; do
  command -v "$command" >/dev/null || die "$command is required; run './kindish setup'"
done

if lsusb -d 1949:9981 >/dev/null 2>&1; then
  printf 'Kindle MTP is already attached (Amazon 1949:9981).\n'
  exit 0
fi

modprobe vhci-hcd

# The MTP daemon is launched early in the stock boot graph, before the Java
# framework has finished registering the USB/volumd event consumers.  Starting
# a cable transition in that window leaves the responder's event queue idle.
framework_ready=0
for _ in {1..180}; do
  probe=$({
    sleep 0.1
    printf '%s\n' \
      '' \
      'value=$(lipc-get-prop -e -i -q com.lab126.kaf frameworkStarted 2>/dev/null || true); [ "$value" = 1 ] && echo __KINDISH_FRAMEWORK_READY__'
    sleep 0.5
  } | socat -T 2 - "UNIX-CONNECT:$VM_DEBUG_SOCKET" 2>/dev/null || true)
  if printf '%s\n' "$probe" | rg -q '^__KINDISH_FRAMEWORK_READY__\r?$'; then
    framework_ready=1
    break
  fi
  sleep 1
done
[[ "$framework_ready" -eq 1 ]] || die "the Kindle framework did not become ready for MTP"

{
  sleep 0.2
  printf '%s\n' \
    '' \
    'initctl stop kindish-mtp-usbip 2>/dev/null || true' \
    'grep -q "^dummy_hcd " /proc/modules || insmod /lib/modules/6.12.89/kernel/drivers/usb/gadget/udc/dummy_hcd.ko' \
    'initctl restart mtp' \
    'initctl start --no-wait kindish-mtp-usbip'
  sleep 1
} | socat - "UNIX-CONNECT:$VM_DEBUG_SOCKET" >/dev/null 2>&1 || \
  die "failed to enable the VM's stock MTP gadget"
available=0
for _ in {1..180}; do
  if usbip --tcp-port 13240 list --remote=127.0.0.1 2>/dev/null | \
      rg -q '1-1:.*1949:9981'; then
    available=1
    break
  fi
  sleep 1
done
[[ "$available" -eq 1 ]] || die "the VM did not export its stock MTP gadget"

usbip --tcp-port 13240 attach --remote=127.0.0.1 --busid=1-1
for _ in {1..100}; do
  lsusb -d 1949:9981 >/dev/null 2>&1 && break
  sleep 0.1
done
lsusb -d 1949:9981 >/dev/null 2>&1 || die "the exported Kindle MTP device did not enumerate"
printf 'Kindle MTP attached from the VM (Amazon 1949:9981).\n'
