#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

KERNEL_VERSION="6.12.89"
KERNEL_SHA256="585afd804a9d2853a353dba5e3ac05627a8186cb1274668f151c0b10250799a0"
KERNEL_TARBALL="$CACHE_DIR/tools/linux-$KERNEL_VERSION.tar.xz"
KERNEL_SOURCE="$CACHE_DIR/tools/linux-$KERNEL_VERSION"
KERNEL_BUILD="$CACHE_DIR/build/linux-$KERNEL_VERSION-kindish"
KERNEL_OUTPUT="$CACHE_DIR/build/kindish-vm-zImage"
MODULE_OUTPUT="$CACHE_DIR/build/kindish-vm-modules/lib/modules/$KERNEL_VERSION/kernel/drivers/usb/gadget/udc/dummy_hcd.ko"
CONFIG_FRAGMENT="$PROJECT_ROOT/vm/kernel.config.fragment"
KERNEL_BOARD_SOURCE="$PROJECT_ROOT/vm/kindish_board.c"
KERNEL_PATCHES=(
  "$PROJECT_ROOT/vm/linux-kindish-board.patch"
  "$PROJECT_ROOT/vm/linux-virtio-eink-ioctls.patch"
  "$PROJECT_ROOT/vm/linux-functionfs-unbind-progress.patch"
  "$PROJECT_ROOT/vm/linux-usbip-dummy-preserve-config.patch"
)

for command in arm-linux-gnueabihf-gcc bison flex make sha256sum tar; do
  command -v "$command" >/dev/null || die "missing VM kernel build command: $command"
done
mkdir -p "$CACHE_DIR/tools" "$CACHE_DIR/build"

if [[ ! -f "$KERNEL_TARBALL" ]]; then
  curl --fail --location --retry 3 \
    --output "$KERNEL_TARBALL.partial" \
    "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KERNEL_VERSION.tar.xz"
  mv "$KERNEL_TARBALL.partial" "$KERNEL_TARBALL"
fi
printf '%s  %s\n' "$KERNEL_SHA256" "$KERNEL_TARBALL" | sha256sum --check

if [[ ! -f "$KERNEL_SOURCE/Makefile" ]]; then
  tar -C "$CACHE_DIR/tools" -xf "$KERNEL_TARBALL"
fi
install -m 0644 "$KERNEL_BOARD_SOURCE" \
  "$KERNEL_SOURCE/drivers/platform/kindish_board.c"
for kernel_patch in "${KERNEL_PATCHES[@]}"; do
  if patch --batch --forward --dry-run --silent -d "$KERNEL_SOURCE" -p1 \
      < "$kernel_patch" >/dev/null 2>&1; then
    patch --batch --forward --silent -d "$KERNEL_SOURCE" -p1 \
      < "$kernel_patch"
  elif ! patch --batch --reverse --dry-run --silent -d "$KERNEL_SOURCE" -p1 \
      < "$kernel_patch" >/dev/null 2>&1; then
    die "Kindish kernel patch does not match Linux $KERNEL_VERSION: $kernel_patch"
  fi
done
mkdir -p "$KERNEL_BUILD"

make -C "$KERNEL_SOURCE" O="$KERNEL_BUILD" ARCH=arm \
  CROSS_COMPILE=arm-linux-gnueabihf- multi_v7_defconfig
"$KERNEL_SOURCE/scripts/kconfig/merge_config.sh" -m -O "$KERNEL_BUILD" \
  "$KERNEL_BUILD/.config" "$CONFIG_FRAGMENT"
make -C "$KERNEL_SOURCE" O="$KERNEL_BUILD" ARCH=arm \
  CROSS_COMPILE=arm-linux-gnueabihf- olddefconfig
make -C "$KERNEL_SOURCE" O="$KERNEL_BUILD" ARCH=arm \
  CROSS_COMPILE=arm-linux-gnueabihf- -j"$(nproc)" \
  zImage drivers/usb/gadget/udc/dummy_hcd.ko
install -m 0644 "$KERNEL_BUILD/arch/arm/boot/zImage" "$KERNEL_OUTPUT"
install -D -m 0644 \
  "$KERNEL_BUILD/drivers/usb/gadget/udc/dummy_hcd.ko" "$MODULE_OUTPUT"
printf '%s\n' "$KERNEL_OUTPUT"
