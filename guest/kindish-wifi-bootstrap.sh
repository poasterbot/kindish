#!/bin/sh
set -eu

control=/var/run/wpa_supplicant

# network-online-start creates and moves the hwsim station asynchronously
# while the rest of KindleOS boots.
tries=0
while ! /sbin/ip link show dev wlan0 >/dev/null 2>&1 && [ "$tries" -lt 30 ]; do
  sleep 1
  tries=$((tries + 1))
done
/sbin/ip link show dev wlan0 >/dev/null 2>&1 || exit 1

tries=0
while ! /usr/bin/lipc-probe -l 2>/dev/null | grep -q '^com.lab126.wifid$'; do
  [ "$tries" -lt 30 ] || exit 1
  sleep 1
  tries=$((tries + 1))
done

# Let wifid finish the initial hardware scan before adding/enabling a profile.
# Starting supplicant with no pre-enabled network keeps nl80211 free for this
# scan and mirrors the stock daemon's ownership of connection policy.
tries=0
while [ "$tries" -lt 65 ]; do
  scan_count="$(/usr/bin/lipc-get-prop com.lab126.wifid scanListCount 2>/dev/null || printf 0)"
  [ "${scan_count:-0}" -gt 0 ] 2>/dev/null && break
  sleep 1
  tries=$((tries + 1))
done
[ "${scan_count:-0}" -gt 0 ] 2>/dev/null || exit 1

# Seed the private simulator AP through wifid's real profile API. Repeating
# createProfile updates the matching profile rather than creating duplicates.
printf '%s\n' \
  '{essid="Kindish Internet", secured="yes", known="yes", key_mgmt="WPA-PSK", psk="kindish-online", store_nw_user_pref="yes", bssid=""}' |
  /usr/bin/lipc-hash-prop com.lab126.wifid createProfile >/dev/null

tries=0
while ! /usr/bin/wpa_cli -p "$control" -i wlan0 list_networks 2>/dev/null |
    grep -q 'Kindish Internet'; do
  [ "$tries" -lt 30 ] || exit 1
  sleep 1
  tries=$((tries + 1))
done

# Ask the stock Wi-Fi daemon to connect the profile it just created. It owns
# supplicant policy and performs DHCP, route, DNS, and LIPC state publication.
/usr/bin/lipc-set-prop com.lab126.wifid cmConnect 0 >/dev/null 2>&1 || true

tries=0
while [ "$tries" -lt 60 ]; do
  if /usr/bin/wpa_cli -p "$control" -i wlan0 status 2>/dev/null |
      grep -q '^wpa_state=COMPLETED$' &&
      /sbin/ip -4 address show dev wlan0 2>/dev/null | grep -q 'inet '; then
    [ ! -s /var/tmp/resolv.conf ] || cp /var/tmp/resolv.conf /var/run/resolv.conf
    exit 0
  fi
  if [ $((tries % 10)) -eq 9 ]; then
    /usr/bin/lipc-set-prop com.lab126.wifid cmConnect 0 >/dev/null 2>&1 || true
  fi
  sleep 1
  tries=$((tries + 1))
done
exit 1
