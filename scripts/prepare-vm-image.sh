#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

VM_IMAGE="$RUNTIME_DIR/kindle-vm-${FIRMWARE_VERSION}-sd.img"
VM_ROOT="$RUNTIME_DIR/vm-root"
VM_KERNEL_VERSION="6.12.89"
VM_DUMMY_HCD="$CACHE_DIR/build/kindish-vm-modules/lib/modules/$VM_KERNEL_VERSION/kernel/drivers/usb/gadget/udc/dummy_hcd.ko"
VM_DEVCAP_SHIM="$($PROJECT_ROOT/scripts/build-vm-devcap-shim.sh)"
VM_POWER_BUTTON="$($PROJECT_ROOT/scripts/build-vm-power-button.sh)"
ROOTFS_PATCHES=(
  "$PROJECT_ROOT/patches/vm-init-hardware-boundary.patch"
  "$PROJECT_ROOT/patches/vm-system-cpufreq-boundary.patch"
  "$PROJECT_ROOT/patches/vm-system-var-move-diagnostics.patch"
  "$PROJECT_ROOT/patches/vm-system-var-move-success-status.patch"
  "$PROJECT_ROOT/patches/vm-disable-hardware-data-layer.patch"
  "$PROJECT_ROOT/patches/vm-debug-console.patch"
  "$PROJECT_ROOT/patches/vm-power-button-hardware-boundary.patch"
  "$PROJECT_ROOT/patches/vm-xorg-virtio.patch"
  "$PROJECT_ROOT/patches/vm-xorg-virtio-multitouch-xkb.patch"
  "$PROJECT_ROOT/patches/vm-xorg-virtio-multitouch-device.patch"
  "$PROJECT_ROOT/patches/vm-xorg-virtio-keyboard-core.patch"
  "$PROJECT_ROOT/patches/vm-xorg-virtio-panel-metrics.patch"
  "$PROJECT_ROOT/patches/vm-browser-qemu-sandbox.patch"
  "$PROJECT_ROOT/patches/vm-browser-virtio-color-depth.patch"
  "$PROJECT_ROOT/patches/vm-browser-appmgr-timeout.patch"
  "$PROJECT_ROOT/patches/vm-framework-hardware-boundary.patch"
  "$PROJECT_ROOT/patches/vm-framework-profile-storage-boundary.patch"
  "$PROJECT_ROOT/patches/vm-framework-timeout.patch"
  "$PROJECT_ROOT/patches/vm-framework-usb-blanket.patch"
  "$PROJECT_ROOT/patches/vm-userstore-mtp-gadget-boundary.patch"
  "$PROJECT_ROOT/patches/vm-wifi-access-point.patch"
  "$PROJECT_ROOT/patches/vm-wifi-access-point-netns.patch"
  "$PROJECT_ROOT/patches/vm-wifi-access-point-iproute2.patch"
  "$PROJECT_ROOT/patches/vm-wifi-access-point-netns-run-dir.patch"
  "$PROJECT_ROOT/patches/vm-wifi-access-point-netns-var-dir.patch"
  "$PROJECT_ROOT/patches/vm-wifi-access-point-phy-netns.patch"
  "$PROJECT_ROOT/patches/vm-wifi-access-point-uplink-policy.patch"
  "$PROJECT_ROOT/patches/vm-wifi-access-point-double-nat.patch"
  "$PROJECT_ROOT/patches/vm-wifi-supplicant-start.patch"
  "$PROJECT_ROOT/patches/vm-mtp-usbip.patch"
  "$PROJECT_ROOT/patches/vm-mtp-usbip-on-demand.patch"
  "$PROJECT_ROOT/patches/vm-mtp-usbip-dummy-module.patch"
  "$PROJECT_ROOT/patches/vm-mtp-usbip-module-path.patch"
  "$PROJECT_ROOT/patches/vm-mtp-usbip-no-module-variable.patch"
  "$PROJECT_ROOT/patches/vm-mtp-usbip-host-module-control.patch"
  "$PROJECT_ROOT/patches/vm-mtp-usbip-manual-compatible.patch"
  "$PROJECT_ROOT/patches/vm-mtp-usbip-stock-lifecycle.patch"
  "$PROJECT_ROOT/patches/vm-mtp-usbip-lipc-ready.patch"
  "$PROJECT_ROOT/patches/vm-mtp-usbip-framework-ready.patch"
)
mounted_loop=""
userstore_loop=""

ensure_loop_devices() {
  # Minimal containers sometimes expose the host loop driver but omit its
  # device nodes. Create only missing nodes; losetup still decides which one is
  # free and owns all attachment/detachment operations.
  [[ -e /dev/loop-control ]] || mknod /dev/loop-control c 10 237
  local index
  for index in $(seq 0 15); do
    [[ -e "/dev/loop${index}" ]] || mknod "/dev/loop${index}" b 7 "$index"
  done
}

ensure_partition_devices() {
  local loop_device="$1"
  local loop_name="${loop_device#/dev/}"
  local attempt sys_partition partition_name major minor

  # The container exposes the loop driver's partition scan, but it does not
  # always run udev to materialize /dev/loopNpM. Create only the exact nodes
  # reported by sysfs for this attached image. Partition scanning is
  # asynchronous and its first sysfs entries can be replaced while GPT is
  # still being read, so wait for the two partitions used below to stabilize.
  for attempt in {1..100}; do
    for sys_partition in /sys/class/block/"$loop_name"p*; do
      [[ -r "$sys_partition/dev" ]] || continue
      partition_name="$(basename "$sys_partition")"
      if IFS=: read -r major minor < "$sys_partition/dev" 2>/dev/null; then
        [[ -e "/dev/$partition_name" ]] || \
          mknod "/dev/$partition_name" b "$major" "$minor"
      fi
    done
    if [[ -r "/sys/class/block/${loop_name}p8/dev" &&
          -r "/sys/class/block/${loop_name}p10/dev" ]]; then
      return
    fi
    sleep 0.05
  done
  die "partition scan did not settle for $loop_device"
}

cleanup() {
  mountpoint -q "$VM_ROOT" && umount "$VM_ROOT"
  [[ -z "$userstore_loop" ]] || losetup -d "$userstore_loop"
  [[ -z "$mounted_loop" ]] || losetup -d "$mounted_loop"
}
trap cleanup EXIT

"$PROJECT_ROOT/scripts/extract-firmware.sh"
ensure_loop_devices
mkdir -p "$RUNTIME_DIR" "$VM_ROOT"
if [[ ! -f "$VM_IMAGE" ]]; then
  # Model the numbered eMMC partitions consumed by the stock layout scripts.
  # Only p8 is populated here; Upstart formats and seeds the writable p5/p9/p10
  # partitions through its normal first-boot jobs.
  truncate -s 4G "$VM_IMAGE.partial"
  sfdisk --quiet "$VM_IMAGE.partial" <<'EOF'
label: gpt
unit: sectors

start=2048, size=16384, name="boot0"
size=16384, name="diagnostics"
size=32768, name="keys"
size=16384, name="misc"
size=131072, name="pdata"
size=16384, name="reserve6"
size=16384, name="hibernate"
size=2097152, name="rootfs"
size=1048576, name="var-local"
name="userstore"
EOF
  loop_device="$(losetup --find --show --partscan "$VM_IMAGE.partial")"
  mounted_loop="$loop_device"
  [[ "$loop_device" =~ ^/dev/loop[0-9]+$ ]] || \
    die "unexpected loop device for VM image: $loop_device"
  ensure_partition_devices "$loop_device"
  dd if="$ROOTFS_IMAGE" of="${loop_device}p8" bs=4M \
    conv=fsync,notrunc status=none
  e2fsck -f -p "${loop_device}p8" >/dev/null || [[ $? -eq 1 ]]
  resize2fs "${loop_device}p8" >/dev/null

  # A retail Kindle's userstore already contains an ext4 filesystem beginning
  # one legacy disk track into its partition. The stock normal-mode boot treats
  # a completely blank userstore as corruption and reboots; creation is reserved
  # for factory-reset/diagnostic flows.
  # QEMU's SDHCI disk reports 16 sectors/track to the ARM guest. Host loop
  # devices report unrelated synthetic geometry, so use the guest-visible
  # value consumed by Kindle's disk_geometry_calc().
  track_sectors=16
  userstore_loop="$(
    losetup --find --show --offset "$((track_sectors * 512))" "${loop_device}p10"
  )"
  mkfs.ext4 -q -F -i 32768 -O encrypt -b 4096 -L Kindle "$userstore_loop"
  tune2fs -i 0 -c 0 -r 89600 -e remount-ro "$userstore_loop" >/dev/null
  losetup -d "$userstore_loop"
  userstore_loop=""

  losetup -d "$loop_device"
  mounted_loop=""
  mv "$VM_IMAGE.partial" "$VM_IMAGE"
fi
if ! mountpoint -q "$VM_ROOT"; then
  loop_device="$(losetup --find --show --partscan "$VM_IMAGE")"
  mounted_loop="$loop_device"
  [[ "$loop_device" =~ ^/dev/loop[0-9]+$ ]] || \
    die "unexpected loop device for VM root: $loop_device"
  ensure_partition_devices "$loop_device"
  mount -o rw "${loop_device}p8" "$VM_ROOT"
fi

mkdir -p "$VM_ROOT/etc/kindish"
for rootfs_patch in "${ROOTFS_PATCHES[@]}"; do
  patch_marker="$VM_ROOT/etc/kindish/.applied-$(basename "$rootfs_patch")"
  [[ ! -e "$patch_marker" ]] || continue
  if patch --batch --forward --dry-run --silent -d "$VM_ROOT" -p1 < "$rootfs_patch"; then
    patch --batch --forward --silent -d "$VM_ROOT" -p1 < "$rootfs_patch"
  elif ! patch --batch --reverse --dry-run --silent -d "$VM_ROOT" -p1 < "$rootfs_patch"; then
    die "VM rootfs patch does not match the runtime image: $rootfs_patch"
  fi
  touch "$patch_marker"
done
# The generic compatibility identity in this OTA reports a 101-DPI,
# 270x360-mm screen. Preserve the vendor implementation and interpose only the
# three panel metrics; every other device capability still uses Amazon's code.
DEVCAP_LIBRARY="$VM_ROOT/usr/lib/libdevice-cap.so.1.0"
DEVCAP_REAL_LIBRARY="$VM_ROOT/usr/lib/libdevice-cap-kindish-real.so.1.0"
if [[ ! -f "$DEVCAP_REAL_LIBRARY" ]]; then
  mv "$DEVCAP_LIBRARY" "$DEVCAP_REAL_LIBRARY"
fi
# Give the preserved implementation a distinct SONAME so the dynamic loader
# can keep it beside the interposer. The replacement is deliberately the same
# byte length and changes only the ELF dynamic string table.
if LC_ALL=C grep -aq 'libdevice-cap.so.1' "$DEVCAP_REAL_LIBRARY"; then
  LC_ALL=C sed -i 's/libdevice-cap\.so\.1/libkindle-cap.so.1/g' \
    "$DEVCAP_REAL_LIBRARY"
fi
ln -sfn libdevice-cap-kindish-real.so.1.0 \
  "$VM_ROOT/usr/lib/libkindle-cap.so.1"
install -m 0755 "$VM_DEVCAP_SHIM" "$DEVCAP_LIBRARY"
install -D -m 0755 "$VM_POWER_BUTTON" \
  "$VM_ROOT/usr/local/sbin/kindish-power-button"
hostapd_binary=$("$PROJECT_ROOT/scripts/fetch-vm-hostapd.sh")
install -D -m 0755 "$hostapd_binary" \
  "$VM_ROOT/usr/local/sbin/kindish-hostapd"
mapfile -t iproute_files < <("$PROJECT_ROOT/scripts/fetch-vm-iproute2.sh")
install -D -m 0755 "${iproute_files[0]}" \
  "$VM_ROOT/usr/local/sbin/kindish-ip"
# Ubuntu builds iproute2 with /run/netns, but Kindle's early init has no /run
# and remounts the stock root filesystem read-only. The equal-length rewrite
# gives this pinned binary a namespace directory on Kindle's writable /var.
LC_ALL=C sed -i 's#/run/netns#/var/netns#g' \
  "$VM_ROOT/usr/local/sbin/kindish-ip"
LC_ALL=C grep -aq '/var/netns' "$VM_ROOT/usr/local/sbin/kindish-ip" || \
  die "failed to adapt iproute2 network namespace directory"
# Remove the empty compatibility directory created by the preceding migration;
# a non-empty path is deliberately preserved.
rmdir "$VM_ROOT/run/netns" "$VM_ROOT/run" 2>/dev/null || true
install -D -m 0644 "${iproute_files[1]}" \
  "$VM_ROOT/usr/local/lib/kindish-iproute2/libbpf.so.0"
install -D -m 0644 "${iproute_files[2]}" \
  "$VM_ROOT/usr/local/lib/kindish-iproute2/libelf.so.1"
install -D -m 0644 "${iproute_files[3]}" \
  "$VM_ROOT/usr/local/lib/kindish-iproute2/libmnl.so.0"
mapfile -t usbip_files < <("$PROJECT_ROOT/scripts/fetch-vm-usbip.sh")
install -D -m 0755 "${usbip_files[0]}" \
  "$VM_ROOT/usr/local/sbin/kindish-usbip"
install -D -m 0755 "${usbip_files[1]}" \
  "$VM_ROOT/usr/local/sbin/kindish-usbipd"
install -D -m 0644 "${usbip_files[2]}" \
  "$VM_ROOT/usr/local/lib/kindish-usbip/libudev.so.1"
[[ -f "$VM_DUMMY_HCD" ]] || \
  die "missing VM dummy_hcd module; run './scripts/build-vm-kernel.sh'"
install -D -m 0644 "$VM_DUMMY_HCD" \
  "$VM_ROOT/lib/modules/$VM_KERNEL_VERSION/kernel/drivers/usb/gadget/udc/dummy_hcd.ko"
sync "$VM_ROOT"
printf '%s\n' "$VM_IMAGE"
