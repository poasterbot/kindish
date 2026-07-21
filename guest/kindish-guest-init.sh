#!/bin/sh
set -eu

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/app/bin
export HOME=/var/tmp/root
export DISPLAY="${DISPLAY:-:0}"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export QEMU_CPU=cortex-a7
export LD_PRELOAD=/usr/local/lib/libkindish-shim.so
export LIBC_FATAL_STDERR_=1
export KINDISH_ONLINE="${KINDISH_ONLINE:-0}"

mkdir -p /var/run/dbus /var/lib/dbus /var/local/kpp /var/tmp/root
[ ! -e /var/run/dbus/pid ] || unlink /var/run/dbus/pid
[ ! -S /var/run/dbus/system_bus_socket ] || unlink /var/run/dbus/system_bus_socket
[ ! -e /var/lock/devcap_shared_data_lock ] || unlink /var/lock/devcap_shared_data_lock
[ ! -e /var/run/KPPMainApp.pid ] || unlink /var/run/KPPMainApp.pid
[ ! -e /var/run/kpp12.pid ] || unlink /var/run/kpp12.pid
[ ! -e /var/run/appmgrd.pid ] || unlink /var/run/appmgrd.pid
dbus-uuidgen --ensure

children=""
start_service() {
  "$@" >>/var/log/kindish-services.log 2>&1 &
  children="$children $!"
}
shutdown() {
  trap - TERM INT EXIT
  for child in $children; do
    kill "$child" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap shutdown TERM INT EXIT

# Kindle daemons log their hardware diagnostics through the image's own
# syslog-ng. It also creates /dev/log before devcap initialization.
/usr/sbin/syslog-ng >>/var/log/kindish-services.log 2>&1 || true
sleep 1

# Populate Lab126's real SysV device-capability segment. The daemon exits after
# initialization by design; every following process shares this IPC namespace.
/usr/bin/devcap-daemon >>/var/log/kindish-services.log 2>&1 || true

# Boot the OTA's own ARM X server and MediaTek e-ink driver. The hardware shim
# redirects /dev/fb0 to the persistent 8-bit gray scanout file and implements
# the standard framebuffer ioctls expected by mtk_drv.so.
x_socket="/var/tmp/.X11-unix/X${DISPLAY#:}"
[ ! -e "$x_socket" ] || unlink "$x_socket"
start_service /usr/bin/Xorg "$DISPLAY" \
  -config /etc/kindish-xorg.conf \
  -logfile /var/log/kindish-Xorg.log \
  -nolisten tcp -noreset -novtswitch -sharevts -keeptty
tries=0
while [ ! -S "$x_socket" ] && [ "$tries" -lt 30 ]; do
  sleep 1
  tries=$((tries + 1))
done
if [ ! -S "$x_socket" ]; then
  printf 'OTA Xorg failed to create %s\n' "$x_socket" >>/var/log/kindish-services.log
  exit 1
fi
{
  printf 'devcap device.name='
  /usr/bin/devcap-get-feature -s device name
  printf 'devcap screen.width='
  /usr/bin/devcap-get-feature -i screen resolution.width
  printf 'display socket: '
  ls -l "/var/tmp/.X11-unix/X${DISPLAY#:}"
} >>/var/log/kindish-services.log 2>&1 || true
start_service /usr/bin/fastmetrics
start_service /usr/bin/dbus-daemon --system --nofork
tries=0
while [ ! -S /var/run/dbus/system_bus_socket ] && [ "$tries" -lt 30 ]; do
  sleep 1
  tries=$((tries + 1))
done
start_service /usr/bin/lipc-daemon -f -p /etc/lipc-daemon-props.conf -e /etc/lipc-daemon-events.conf

if [ "$KINDISH_ONLINE" = 1 ]; then
  # Run the OTA's own supplicant, Wi-Fi daemon, and connection manager. These
  # named QEMU wrappers add generic-netlink pass-through while preserving the
  # process names Kindle's service scripts expect.
  start_service /usr/local/libexec/kindish/wpa_supplicant \
    -L / -E LD_PRELOAD=/usr/local/lib/libkindish-shim.so \
    /usr/bin/wpa_supplicant -t -D nl80211 -i wlan0 \
    -c /etc/kindish-wpa-supplicant.conf
  tries=0
  while [ ! -S /var/run/wpa_supplicant/wlan0 ] && [ "$tries" -lt 30 ]; do
    sleep 1
    tries=$((tries + 1))
  done
  start_service /usr/local/libexec/kindish/wifid \
    -L / -E LD_PRELOAD=/usr/local/lib/libkindish-shim.so \
    /usr/local/libexec/kindish/wifid-arm -f -n -r
  start_service /usr/local/libexec/kindish/cmd \
    -L / -E LD_PRELOAD=/usr/local/lib/libkindish-shim.so \
    /usr/sbin/cmd -f
  /usr/local/bin/kindish-wifi-bootstrap \
    >>/var/log/kindish-services.log 2>&1 ||
    printf 'Kindle Wi-Fi bootstrap did not reach connected state\n' \
      >>/var/log/kindish-services.log
fi

# Reproduce the KPP Upstart pre-start registration. libappreg creates its
# schema on the first open, so a second pass makes a pristine image converge
# without replacing any Amazon data.
for pass in 1 2; do
  /usr/bin/register /app/registry/kppmainapp.install >>/var/log/kindish-services.log 2>&1 || true
  /usr/bin/register /app/registry/kppstore.install >>/var/log/kindish-services.log 2>&1 || true
  /usr/bin/register /app/registry/kpp_home_default_app.install >>/var/log/kindish-services.log 2>&1 || true
  if [ "$KINDISH_ONLINE" = 1 ]; then
    /usr/bin/register /etc/kindish-oobe.install >>/var/log/kindish-services.log 2>&1 || true
  fi
done
# The physical boot sequence sets portrait display mode before the Java KAF
# services start. This writes only the runtime dynconfig database.
/usr/bin/set-dynconf-value current.display.mode 0 >>/var/log/kindish-services.log 2>&1 || true
# appmgrd and KPP both perform a burst of legacy LIPC registration at boot.
# On qemu-user, serializing those bursts avoids a translated-futex stall while
# still bringing the real application manager online before user interaction.
start_service /bin/sh -c 'sleep 75; exec /usr/bin/appmgrd'
start_service /bin/sh -c 'sleep 90; exec /usr/local/bin/kindish-framework-launch'
start_service /bin/sh -c 'sleep 90; exec /usr/local/bin/kindish-launch-home'

# The actual KPP application from Amazon's 5.19.2 image. It remains the
# foreground child so the host supervisor has an honest liveness signal.
sleep 1
/app/bin/KPPMainApp >>/var/log/kindish-kpp.log 2>&1 &
app_pid=$!
children="$children $app_pid"
set +e
wait "$app_pid"
app_status=$?
printf 'KPPMainApp exited with status %s\n' "$app_status" >>/var/log/kindish-services.log
exit "$app_status"
