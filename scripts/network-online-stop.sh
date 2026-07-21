#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

[[ -e "$PID_DIR/network-online" ]] || exit 0

for name in dnsmasq hostapd; do
  pid_file="$PID_DIR/$name.pid"
  if pid_alive "$pid_file"; then
    kill -- "-$(<"$pid_file")" 2>/dev/null || kill "$(<"$pid_file")" 2>/dev/null || true
  fi
done

while iptables -t nat -C POSTROUTING -s 10.177.0.0/24 \
    -m comment --comment kindish-online -j MASQUERADE 2>/dev/null; do
  iptables -t nat -D POSTROUTING -s 10.177.0.0/24 \
    -m comment --comment kindish-online -j MASQUERADE
done
while iptables -C FORWARD -i kindish-ap \
    -m comment --comment kindish-online -j ACCEPT 2>/dev/null; do
  iptables -D FORWARD -i kindish-ap \
    -m comment --comment kindish-online -j ACCEPT
done
while iptables -C FORWARD -o kindish-ap -m conntrack --ctstate RELATED,ESTABLISHED \
    -m comment --comment kindish-online -j ACCEPT 2>/dev/null; do
  iptables -D FORWARD -o kindish-ap -m conntrack --ctstate RELATED,ESTABLISHED \
    -m comment --comment kindish-online -j ACCEPT
done

modprobe -r mac80211_hwsim 2>/dev/null || true
if [[ -s "$PID_DIR/ip-forward.previous" ]]; then
  previous="$(<"$PID_DIR/ip-forward.previous")"
  [[ "$previous" != 0 ]] || sysctl -q -w net.ipv4.ip_forward=0
fi

for name in dnsmasq hostapd; do
  pid_file="$PID_DIR/$name.pid"
  [[ ! -e "$pid_file" ]] || unlink "$pid_file"
done
[[ ! -e "$PID_DIR/ip-forward.previous" ]] || unlink "$PID_DIR/ip-forward.previous"
unlink "$PID_DIR/network-online"
