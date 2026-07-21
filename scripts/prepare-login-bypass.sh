#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

[[ -f "$PATCHED_HBC" ]] && exit 0
[[ -f "$ROOT_DIR/app/KPPMainApp/js/KPPMainApp.js.hbc" ]] || \
  die "mount the extracted runtime before preparing the KPP patch"
command -v python3 >/dev/null || die "python3 is required"
python3 -m pip --version >/dev/null 2>&1 || die "python3-pip is required"

repo="$CACHE_DIR/tools/KPP_Patch"
python_dir="$CACHE_DIR/tools/kpp-python"
mkdir -p "$CACHE_DIR/tools" "$CACHE_DIR/patches"
if [[ ! -d "$repo/.git" ]]; then
  git clone --depth 1 https://github.com/KindleModding/KPP_Patch.git "$repo"
fi
if [[ ! -d "$python_dir/kpp_patch" ]]; then
  python3 -m pip install --target "$python_dir" --ignore-requires-python "$repo"
fi

# hbctool uses Python 3.13's one-argument Generator default. Keep the dependency
# otherwise unchanged when the host distribution still ships Python 3.12.
if [[ "$(python3 -c 'import sys; print(sys.version_info < (3, 13))')" == True ]]; then
  sed -i \
    's/Generator\[InstructionDisassembled\]/Generator[InstructionDisassembled, None, None]/' \
    "$python_dir/hbctool/hbc/hbc84/__init__.py"
fi

source_hbc="$CACHE_DIR/patches/KPPMainApp.js.hbc"
cp --reflink=auto "$ROOT_DIR/app/KPPMainApp/js/KPPMainApp.js.hbc" "$source_hbc"
PYTHONPATH="$python_dir" python3 -m kpp_patch --no-interactive \
  --patch_registration_detection "$source_hbc"
[[ -f "$PATCHED_HBC" ]] || die "KPP registration patch did not produce output"
printf 'Prepared reversible registration bypass: %s\n' "$PATCHED_HBC"
