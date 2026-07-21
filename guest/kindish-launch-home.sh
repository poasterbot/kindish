#!/bin/sh
set -eu

# The physical Upstart graph asks appmgrd to foreground the default booklet
# after the Java framework announces readiness. Reproduce that transition
# without starting the device-only power, Wi-Fi, and update jobs.
tries=0
while [ "$tries" -lt 90 ]; do
  framework_started="$(/usr/bin/lipc-get-prop com.lab126.kaf frameworkStarted 2>/dev/null || true)"
  if [ "$framework_started" = "1" ]; then
    if [ "${KINDISH_ONLINE:-0}" = 1 ]; then
      /usr/bin/lipc-set-prop com.lab126.appmgrd start 'app://com.lab126.oobe?view=Register'
    else
      /usr/bin/lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
    fi
    exit 0
  fi
  sleep 2
  tries=$((tries + 1))
done

printf 'Timed out waiting for the Kindle Java framework\n' >&2
exit 1
