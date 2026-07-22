#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

QEMU_COMMIT="11aa0b1ff115b86160c4d37e7c37e6a6b13b77ea"
QEMU_SOURCE="$CACHE_DIR/tools/qemu-$QEMU_COMMIT"
QEMU_BUILD="$QEMU_SOURCE/build-kindish-system"
QEMU_OUTPUT="$CACHE_DIR/build/qemu-system-arm-kindish"
PATCH_FILES=(
  "$PROJECT_ROOT/patches/qemu-vnc-multitouch.patch"
  "$PROJECT_ROOT/patches/qemu-kindle-power-button.patch"
  "$PROJECT_ROOT/patches/qemu-repeatable-power-button.patch"
)
STAMP="$CACHE_DIR/build/qemu-system-arm-kindish.stamp"
patch_hash="$(sha256sum "${PATCH_FILES[@]}" | sha256sum | awk '{print $1}')"
expected_stamp="$QEMU_COMMIT $patch_hash"

if [[ -x "$QEMU_OUTPUT" && -f "$STAMP" && "$(<"$STAMP")" == "$expected_stamp" ]]; then
  printf '%s\n' "$QEMU_OUTPUT"
  exit 0
fi

for command in git ninja pkg-config python3; do
  command -v "$command" >/dev/null || die "missing QEMU build command: $command"
done
pkg-config --exists glib-2.0 pixman-1 slirp || \
  die "missing QEMU build libraries; run './kindish setup'"
[[ -f /usr/include/libfdt.h ]] || \
  die "missing libfdt headers; run './kindish setup'"

mkdir -p "$CACHE_DIR/tools" "$CACHE_DIR/build"
if [[ ! -d "$QEMU_SOURCE/.git" ]]; then
  git clone --filter=blob:none --no-checkout \
    https://gitlab.com/qemu-project/qemu.git "$QEMU_SOURCE"
  git -C "$QEMU_SOURCE" checkout --detach "$QEMU_COMMIT"
fi
[[ "$(git -C "$QEMU_SOURCE" rev-parse HEAD)" == "$QEMU_COMMIT" ]] || \
  die "$QEMU_SOURCE is not the pinned QEMU source"

for patch_file in "${PATCH_FILES[@]}"; do
  if git -C "$QEMU_SOURCE" apply --check "$patch_file" 2>/dev/null; then
    git -C "$QEMU_SOURCE" apply "$patch_file"
  elif ! git -C "$QEMU_SOURCE" apply --reverse --check "$patch_file" 2>/dev/null; then
    die "cached QEMU source has unexpected changes for $(basename "$patch_file")"
  fi
done

if [[ ! -f "$QEMU_BUILD/build.ninja" ]]; then
  mkdir -p "$QEMU_BUILD"
  (
    cd "$QEMU_BUILD"
    ../configure \
      --target-list=arm-softmmu \
      --disable-docs \
      --disable-guest-agent \
      --disable-tools \
      --enable-slirp \
      --enable-vnc >&2
  )
fi
ninja -C "$QEMU_BUILD" qemu-system-arm >&2
install -m 0755 "$QEMU_BUILD/qemu-system-arm" "$QEMU_OUTPUT"
printf '%s\n' "$expected_stamp" > "$STAMP"
printf '%s\n' "$QEMU_OUTPUT"
