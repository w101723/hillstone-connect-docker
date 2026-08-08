#!/usr/bin/env bash
set -euo pipefail

curl -fsS http://127.0.0.1:6080/vnc.html >/dev/null

for program in dbus hillstone-service desktop novnc route-guard; do
  supervisorctl status "$program" | grep -q 'RUNNING'
done

ss -lntp | grep -qE '127\.0\.0\.1:35421\b.*HillstoneSecure'
ss -lnt | grep -qE '127\.0\.0\.1:5901\b'

if [[ -s /run/hillstone-vpn/interface ]]; then
  iface=$(</run/hillstone-vpn/interface)
  ip link show dev "$iface" >/dev/null
fi
