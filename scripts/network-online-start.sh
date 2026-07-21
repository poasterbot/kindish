#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
need_root

supervisor_pid="${1:-}"
[[ "$supervisor_pid" =~ ^[0-9]+$ ]] && kill -0 "$supervisor_pid" 2>/dev/null || \
  die "online networking needs a live KindleOS supervisor PID"

for command in hostapd dnsmasq iptables iw nsenter; do
  command -v "$command" >/dev/null || \
    die "$command is required for online mode; run 'mise run setup'"
done
[[ ! -e "$PID_DIR/network-online" ]] || die "online networking is already configured"
[[ ! -d /sys/module/mac80211_hwsim ]] || \
  die "mac80211_hwsim is already in use; stop its existing user before starting Kindish online"
[[ ! -e /sys/class/net/kindish-ap ]] || die "host interface kindish-ap already exists"

mkdir -p "$PID_DIR" "$LOG_DIR"
printf '%s\n' "$(sysctl -n net.ipv4.ip_forward)" > "$PID_DIR/ip-forward.previous"
touch "$PID_DIR/network-online"

cleanup_on_error() {
  "$PROJECT_ROOT/scripts/network-online-stop.sh" >/dev/null 2>&1 || true
}
trap cleanup_on_error ERR

modprobe mac80211_hwsim radios=2
mapfile -t radios < <(
  for interface_path in /sys/class/net/*; do
    [[ -L "$interface_path/phy80211" ]] || continue
    [[ "$(readlink -f "$interface_path/device/driver/module" 2>/dev/null || true)" == \
      */mac80211_hwsim ]] || continue
    basename "$interface_path"
  done | sort
)
[[ ${#radios[@]} -eq 2 ]] || die "expected two mac80211_hwsim radios"

ap_interface="${radios[0]}"
client_interface="${radios[1]}"
client_phy="$(basename "$(readlink -f "/sys/class/net/$client_interface/phy80211")")"
ip link set "$ap_interface" name kindish-ap
iw phy "$client_phy" set netns "$supervisor_pid"
nsenter -t "$supervisor_pid" -n ip link set lo up
nsenter -t "$supervisor_pid" -n ip link set "$client_interface" name wlan0
nsenter -t "$supervisor_pid" -n ip link set wlan0 up

nohup setsid hostapd "$PROJECT_ROOT/guest/kindish-hostapd.conf" \
  >"$LOG_DIR/hostapd.log" 2>&1 </dev/null &
printf '%s\n' "$!" > "$PID_DIR/hostapd.pid"
for _ in {1..100}; do
  ip link show kindish-ap 2>/dev/null | grep -q 'UP' && break
  pid_alive "$PID_DIR/hostapd.pid" || die "virtual Wi-Fi access point failed to start"
  sleep 0.05
done
ip address add 10.177.0.1/24 dev kindish-ap
ip link set kindish-ap up

nohup setsid dnsmasq --keep-in-foreground \
  --interface=kindish-ap --bind-interfaces --except-interface=lo \
  --dhcp-range=10.177.0.10,10.177.0.50,255.255.255.0,1h \
  --dhcp-option=3,10.177.0.1 --dhcp-option=6,10.177.0.1 \
  --log-facility=- >"$LOG_DIR/dnsmasq.log" 2>&1 </dev/null &
printf '%s\n' "$!" > "$PID_DIR/dnsmasq.pid"

sysctl -q -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -s 10.177.0.0/24 \
  -m comment --comment kindish-online -j MASQUERADE
iptables -A FORWARD -i kindish-ap \
  -m comment --comment kindish-online -j ACCEPT
iptables -A FORWARD -o kindish-ap -m conntrack --ctstate RELATED,ESTABLISHED \
  -m comment --comment kindish-online -j ACCEPT

trap - ERR
printf 'Virtual WPA2 adapter ready (wlan0, SSID "Kindish Internet").\n'
