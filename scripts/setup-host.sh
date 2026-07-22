#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

command -v mise >/dev/null || \
  die "mise is required; install it from https://mise.jdx.dev/getting-started/"
mise --cd "$PROJECT_ROOT" bootstrap --yes
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  "linux-modules-extra-$(uname -r)" \
  "linux-tools-$(uname -r)"
"$PROJECT_ROOT/scripts/build-vm-kernel.sh"
