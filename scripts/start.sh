#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

[[ $# -eq 0 ]] || die "usage: ./kindish start"
for command in socat websockify; do
  command -v "$command" >/dev/null || die "$command is required; run './kindish setup'"
done

VM_IMAGE="$RUNTIME_DIR/kindle-vm-${FIRMWARE_VERSION}-sd.img"
VM_KERNEL="$CACHE_DIR/build/kindish-vm-zImage"
VM_DUMMY_HCD="$CACHE_DIR/build/kindish-vm-modules/lib/modules/6.12.89/kernel/drivers/usb/gadget/udc/dummy_hcd.ko"
VM_PID_FILE="$RUNTIME_DIR/kindish-vm.pid"
VM_QMP_SOCKET="$RUNTIME_DIR/kindish-qmp.sock"
VM_DEBUG_SOCKET="$RUNTIME_DIR/kindish-debug.sock"
VM_CONSOLE_LOG="$RUNTIME_DIR/kindish-vm-console.log"
QEMU_SYSTEM_ARM="$($PROJECT_ROOT/scripts/build-qemu-system-arm.sh)"

if pid_alive "$VM_PID_FILE"; then
  die "Kindle VM is already running (PID $(<"$VM_PID_FILE"))"
fi

[[ -f "$VM_KERNEL" && -f "$VM_DUMMY_HCD" ]] || \
  "$PROJECT_ROOT/scripts/build-vm-kernel.sh" >/dev/null
"$PROJECT_ROOT/scripts/prepare-vm-image.sh" >/dev/null

mkdir -p "$RUNTIME_DIR" "$LOG_DIR" "$PID_DIR"
for stale in "$VM_PID_FILE" "$VM_QMP_SOCKET" "$VM_DEBUG_SOCKET"; do
  [[ ! -e "$stale" ]] || unlink "$stale"
done
: > "$VM_CONSOLE_LOG"

(( VNC_PORT >= 5900 )) || die "KINDISH_VNC_PORT must be at least 5900"
vnc_display=$((VNC_PORT - 5900))

"$QEMU_SYSTEM_ARM" \
  -L /usr/share/qemu \
  -L /usr/lib/ipxe/qemu \
  -M virt,highmem=off \
  -accel tcg,thread=multi \
  -cpu cortex-a15 \
  -m 640M \
  -smp 2 \
  -display none \
  -audio driver=none \
  -vnc "127.0.0.1:$vnc_display" \
  -no-reboot \
  -daemonize \
  -pidfile "$VM_PID_FILE" \
  -kernel "$VM_KERNEL" \
  -append "console=ttyAMA0,115200 earlycon=pl011,0x09000000 rw rootwait loglevel=4 ip=dhcp root=/dev/mmcblk0p8" \
  -drive "file=$VM_IMAGE,format=raw,if=none,id=kindle-root" \
  -device sdhci-pci \
  -device sd-card,drive=kindle-root \
  -netdev user,id=uplink,hostfwd=tcp:127.0.0.1:10022-:22,hostfwd=tcp:127.0.0.1:13240-:3240 \
  -device virtio-net-pci,netdev=uplink \
  -device virtio-rng-pci \
  -device virtio-gpu-pci,xres=1072,yres=1448 \
  -device virtio-keyboard-pci \
  -device virtio-multitouch-pci \
  -device virtio-serial-pci \
  -chardev "socket,id=debug,path=$VM_DEBUG_SOCKET,server=on,wait=off" \
  -device virtconsole,chardev=debug \
  -chardev "file,id=serial,path=$VM_CONSOLE_LOG" \
  -serial chardev:serial \
  -qmp "unix:$VM_QMP_SOCKET,server=on,wait=off"

nohup setsid websockify --web=/usr/share/novnc/ \
  "127.0.0.1:$NOVNC_PORT" "127.0.0.1:$VNC_PORT" \
  >"$LOG_DIR/novnc.log" 2>&1 </dev/null &
printf '%s\n' "$!" > "$PID_DIR/novnc.pid"

for _ in {1..100}; do
  [[ -S "$VM_QMP_SOCKET" ]] && break
  pid_alive "$VM_PID_FILE" || die "Kindle VM exited during startup; see $VM_CONSOLE_LOG"
  sleep 0.1
done
[[ -S "$VM_QMP_SOCKET" ]] || die "Kindle VM did not create its monitor socket"

printf 'KindleOS %s full-system VM is running.\n' "$FIRMWARE_VERSION"
printf '  Browser: http://127.0.0.1:%s/vnc.html?autoconnect=1&resize=scale\n' "$NOVNC_PORT"
printf '  VNC:     127.0.0.1:%s\n' "$VNC_PORT"
printf '  SSH:     127.0.0.1:10022\n'
printf '  Console: %s\n' "$VM_CONSOLE_LOG"
