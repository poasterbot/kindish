#!/bin/sh
set -eu

export DISPLAY="${DISPLAY:-:0}"
export LD_PRELOAD=/usr/local/lib/libkindish-shim.so
exec /app/KPPOOBEMainApp/bin/OOBEApplication \
  -c /app/KPPOOBEMainApp/static/config "$@"
