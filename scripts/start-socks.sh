#!/usr/bin/env bash
set -euo pipefail

state=/run/hillstone-vpn/interface
iface=eth0

if [[ -s "$state" ]]; then
  candidate=$(<"$state")
  if ip link show dev "$candidate" >/dev/null 2>&1; then
    iface=$candidate
  else
    rm -f "$state"
  fi
fi

sed "s/^external:.*/external: ${iface}/" /etc/danted.conf.template >/run/danted/danted.conf
exec /usr/sbin/danted -f /run/danted/danted.conf
