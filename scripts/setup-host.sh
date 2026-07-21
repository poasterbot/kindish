#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  binfmt-support build-essential curl e2fsprogs file gcc-arm-linux-gnueabihf iproute2 \
  git libarchive-dev libssl-dev linux-headers-"$(uname -r)" linux-modules-extra-"$(uname -r)" \
  linux-tools-"$(uname -r)" make novnc python3-pip qemu-user-static \
  u-boot-tools usbutils mtp-tools util-linux websockify x11-utils x11vnc xdotool zlib1g-dev
"$PROJECT_ROOT/scripts/build-dummy-hcd.sh" >/dev/null
printf 'Host dependencies installed. Run: %s/kindish start\n' "$PROJECT_ROOT"
