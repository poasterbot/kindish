#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

"$PROJECT_ROOT/scripts/extract-firmware.sh"
mkdir -p "$LOWER_DIR" "$ROOT_DIR" "$RUNTIME_DIR" "$USERSTORE_DIR"
mkdir -p "$USERSTORE_DIR/system/fmcache"
chown -R 9000:150 "$USERSTORE_DIR"
chmod 0775 "$USERSTORE_DIR" "$USERSTORE_DIR/system" "$USERSTORE_DIR/system/fmcache"
is_mounted "$LOWER_DIR" || mount -o ro,loop "$ROOTFS_IMAGE" "$LOWER_DIR"
if [[ ! -f "$RUNTIME_IMAGE" ]]; then
  cp --reflink=auto --sparse=always "$ROOTFS_IMAGE" "$RUNTIME_IMAGE.partial"
  mv "$RUNTIME_IMAGE.partial" "$RUNTIME_IMAGE"
fi
is_mounted "$ROOT_DIR" || mount -o rw,loop "$RUNTIME_IMAGE" "$ROOT_DIR"

# KindleOS keeps large, rarely changed trees in squashfs images. Recreate the
# device's loopback table in the writable runtime clone. The verified Amazon
# image remains mounted read-only and is never modified.
while IFS= read -r guest_path; do
  [[ -n "$guest_path" && "$guest_path" != \#* ]] || continue
  image="$LOWER_DIR${guest_path}.sqsh"
  target="$ROOT_DIR$guest_path"
  [[ -f "$image" && -d "$target" ]] || continue
  is_mounted "$target" || mount -o ro,loop -t squashfs "$image" "$target"
done < "$LOWER_DIR/etc/loopbacktab"

# Patch a copy of the actual Hermes UI bundle, then bind it over the read-only
# squashfs file. The signed OTA and extracted root image are never changed.
"$PROJECT_ROOT/scripts/prepare-login-bypass.sh"
is_mounted "$ROOT_DIR/app/KPPMainApp/js/KPPMainApp.js.hbc" || \
  mount --bind "$PATCHED_HBC" "$ROOT_DIR/app/KPPMainApp/js/KPPMainApp.js.hbc"

mkdir -p "$ROOT_DIR/mnt/us" "$ROOT_DIR/mnt/base-us" "$ROOT_DIR/proc" "$ROOT_DIR/sys" "$ROOT_DIR/dev" "$ROOT_DIR/var/tmp/.X11-unix"
is_mounted "$ROOT_DIR/mnt/us" || mount --bind "$USERSTORE_DIR" "$ROOT_DIR/mnt/us"
is_mounted "$ROOT_DIR/mnt/base-us" || mount --bind "$USERSTORE_DIR" "$ROOT_DIR/mnt/base-us"
is_mounted "$ROOT_DIR/proc" || mount -t proc proc "$ROOT_DIR/proc"
is_mounted "$ROOT_DIR/sys" || mount --rbind /sys "$ROOT_DIR/sys"
mount -o remount,ro,bind "$ROOT_DIR/sys" 2>/dev/null || true

if ! is_mounted "$ROOT_DIR/dev"; then
  mount -t tmpfs -o mode=755,nosuid,noexec tmpfs "$ROOT_DIR/dev"
  mkdir -p "$ROOT_DIR/dev/pts" "$ROOT_DIR/dev/shm" "$ROOT_DIR/dev/input" "$ROOT_DIR/dev/usb-ffs"
  mknod -m 666 "$ROOT_DIR/dev/null" c 1 3
  mknod -m 666 "$ROOT_DIR/dev/zero" c 1 5
  mknod -m 666 "$ROOT_DIR/dev/random" c 1 8
  mknod -m 666 "$ROOT_DIR/dev/urandom" c 1 9
  mknod -m 666 "$ROOT_DIR/dev/tty" c 5 0
  mount -t devpts devpts "$ROOT_DIR/dev/pts"
  mount -t tmpfs -o mode=1777 tmpfs "$ROOT_DIR/dev/shm"
fi
is_mounted "$ROOT_DIR/var/tmp/.X11-unix" || mount --bind /tmp/.X11-unix "$ROOT_DIR/var/tmp/.X11-unix"

mkdir -p "$ROOT_DIR/var/local/system" "$ROOT_DIR/var/local/kpp" \
  "$ROOT_DIR/var/local/java/prefs" "$ROOT_DIR/var/run/dbus" "$ROOT_DIR/var/log" "$ROOT_DIR/var/tmp/root"
chmod 1777 "$ROOT_DIR/var/tmp"
chmod 0777 "$ROOT_DIR/var/tmp/root" "$ROOT_DIR/var/local/kpp"

# A stable synthetic device identity. No Amazon credentials or service calls.
mkdir -p "$ROOT_DIR/var/local/kindish/proc" "$ROOT_DIR/var/local/kindish/dev" "$ROOT_DIR/usr/local/lib"
printf 'B0D4KINDISHKT6001\n' > "$ROOT_DIR/var/local/system/DSN"
# `board_id` is a hardware board family, not the retail serial device code.
# The KT6 recovery image names this Rossini (`ri7` in Lab126 devcap tables).
printf '0003M50000000000\n' > "$ROOT_DIR/var/local/kindish/proc/board_id"
printf 'B0D4KINDISHKT6001\n' > "$ROOT_DIR/var/local/kindish/proc/usid"
printf 'Amazon Kindle\n' > "$ROOT_DIR/var/local/kindish/proc/product_name"
printf '0x0324\n' > "$ROOT_DIR/var/local/kindish/proc/productid"
printf 'A2AJ1N357FEMTV\n' > "$ROOT_DIR/var/local/kindish/proc/device_type_id"
truncate -s $((1072 * 1448)) "$ROOT_DIR/var/local/kindish/dev/fb0"
truncate -s 1G "$ROOT_DIR/var/local/kindish/dev/varlocal.img"
# The real Upstart framework job grants the framework user (uid 9000, group
# javausers 150) write access to these runtime trees before KPP starts.
for framework_dir in var/local var/log var/lock var/run; do
  chgrp -R 150 "$ROOT_DIR/$framework_dir"
  chmod -R g=u "$ROOT_DIR/$framework_dir"
done
python3 "$PROJECT_ROOT/scripts/init-content-catalog.py" "$ROOT_DIR"
chown 9000:150 "$ROOT_DIR/var/local/cc.db"
chmod 0664 "$ROOT_DIR/var/local/cc.db"
"$PROJECT_ROOT/scripts/build-shim.sh" >/dev/null
install -m 0755 "$CACHE_DIR/build/libkindish-shim.so" "$ROOT_DIR/usr/local/lib/libkindish-shim.so"
install -m 0755 "$PROJECT_ROOT/guest/kindish-framework-launch.sh" \
  "$ROOT_DIR/usr/local/bin/kindish-framework-launch"
install -m 0755 "$PROJECT_ROOT/guest/kindish-launch-home.sh" \
  "$ROOT_DIR/usr/local/bin/kindish-launch-home"
install -m 0755 "$PROJECT_ROOT/guest/kindish-mtp-hw.sh" \
  "$ROOT_DIR/usr/bin/mtp.sh"
install -m 0644 "$PROJECT_ROOT/guest/kindish-xorg.conf" \
  "$ROOT_DIR/etc/kindish-xorg.conf"
install -m 0644 "$PROJECT_ROOT/guest/fontconfig-local.conf" \
  "$ROOT_DIR/etc/fonts/local.conf"
install -m 0644 "$PROJECT_ROOT/guest/session_token" \
  "$ROOT_DIR/var/tmp/session_token"
printf '%s\n' 'LANG=en_US.UTF-8' 'LC_ALL=en_US.UTF-8' > "$ROOT_DIR/var/local/system/locale"
touch "$ROOT_DIR/var/local/system/factory_fresh"
# The Java framework uses this persistent preference-file sentinel to decide
# that first-run OOBE has already completed. No credentials are fabricated.
install -o 9000 -g 150 -m 0664 "$PROJECT_ROOT/guest/home.preferences" \
  "$ROOT_DIR/var/local/java/prefs/com.lab126.booklet.home.preferences"

# A factory image normally imports these OTA-supplied application records on
# first boot. Running the stock merger is idempotent and makes the actual Home,
# BookletManager, settings, reader, and KAF services available to appmgrd.
chroot "$ROOT_DIR" /usr/bin/register -m /opt/var/local/reg/prereg.db >/dev/null 2>&1 || true
chroot "$ROOT_DIR" /usr/bin/register -m /opt/var/local/reg/ServerConfig.db >/dev/null 2>&1 || true
chown 9000:150 "$ROOT_DIR/var/local/appreg.db"
chmod 0664 "$ROOT_DIR/var/local/appreg.db"

# Generate ARM fontconfig caches once so Pango/Cairo can render the OTA's
# Amazon Ember family. Subsequent boots reuse the writable runtime cache.
font_marker="$ROOT_DIR/var/cache/fontconfig/.kindish-java-fonts"
if [[ ! -e "$font_marker" ]]; then
  chroot "$ROOT_DIR" /usr/bin/fc-cache -f >/dev/null 2>&1
  touch "$font_marker"
fi
printf 'Runtime mounted at %s\n' "$ROOT_DIR"
