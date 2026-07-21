#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

command -v mise >/dev/null || \
  die "mise is required; install it from https://mise.jdx.dev/getting-started/"
exec mise --cd "$PROJECT_ROOT" bootstrap --yes
