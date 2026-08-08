#!/usr/bin/env bash
set -euo pipefail

state_dir=/run/hillstone-vpn
mkdir -p "$state_dir"
regex=${VPN_TUN_REGEX:-'^(tun|tap|ppp|hsc|sc)[0-9_-]*$'}

candidates=$(ip -j -d link show | jq -r --arg regex "$regex" '
  .[] |
  select(.ifname != "lo" and .ifname != "eth0") |
  select(.operstate == "UP" or (.flags | index("UP"))) |
  select(.ifname | test($regex; "i")) |
  .ifname')

for iface in $candidates; do
  if ip -j addr show dev "$iface" | jq -e '.[0].addr_info | length > 0' >/dev/null; then
    if [[ -n "${VPN_PROBE_HOST:-}" ]]; then
      if ! ip route get "$VPN_PROBE_HOST" | grep -q "dev $iface"; then
        continue
      fi
    elif ! ip route show table all dev "$iface" | grep -q .; then
      continue
    fi
    printf '%s\n' "$iface" | tee "$state_dir/interface"
    exit 0
  fi
done

rm -f "$state_dir/interface"
exit 1
