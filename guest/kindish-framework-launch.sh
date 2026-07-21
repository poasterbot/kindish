#!/bin/sh
set -eu

# framework.conf normally performs this ownership/setgid pass before invoking
# /etc/upstart/framework. The standalone supervisor must reproduce it because
# CVM drops to the OTA's `framework` account through libenvload.
mkdir -p /var/log/osgicache
chown root:150 /var/log/osgicache
chmod 2775 /var/log/osgicache

# The stock framework launcher replaces LD_PRELOAD with Kindle's global-dlopen
# helper. Preserve that helper and append the narrowly scoped hardware shim so
# the real CVM/OSGi home framework sees the same KT6 identity as KPP.
launcher=/var/tmp/kindish-framework
sed \
  -e 's|export LD_PRELOAD="$JLIB/arm/libdlopen_global.so"|export LD_PRELOAD="$JLIB/arm/libdlopen_global.so:/usr/local/lib/libkindish-shim.so"|' \
  -e 's|-Dgci.useAcceleratedSurface=true|-Dgci.useAcceleratedSurface=false|' \
  -e 's|-Dx11.shmem=true|-Dx11.shmem=false|' \
  /etc/upstart/framework > "$launcher"
chmod 0755 "$launcher"
exec "$launcher"
