#!/usr/bin/env bash
set -euo pipefail

[[ $(< /proc/sys/net/ipv4/ip_forward) == 1 ]]
for chain in INPUT FORWARD OUTPUT; do
  iptables -S "$chain" | grep -qx -- "-P $chain ACCEPT"
done
iptables -t nat -C POSTROUTING -m addrtype ! --src-type LOCAL -j MASQUERADE
! iptables -t nat -C POSTROUTING -j MASQUERADE 2>/dev/null

curl -fsS http://127.0.0.1:6080/vnc.html >/dev/null

for program in dbus hillstone-service desktop novnc socks; do
  supervisorctl status "$program" | grep -q 'RUNNING'
done

ss -lntp | grep -qE '127\.0\.0\.1:35421\b.*HillstoneSecure'
ss -lnt | grep -qE '127\.0\.0\.1:5901\b'
ss -lnt | grep -qE '0\.0\.0\.0:1080\b'
pgrep -u 0 -f '^/usr/local/bin/gost ' >/dev/null

! iptables -S | grep -qE 'HILLSTONE_GOST_|--uid-owner'
