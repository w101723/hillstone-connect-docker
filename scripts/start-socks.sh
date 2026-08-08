#!/usr/bin/env bash
set -euo pipefail

state=/run/hillstone-vpn/interface
while [[ ! -s "$state" ]]; do
  /usr/local/bin/detect-vpn-interface.sh >/dev/null 2>&1 || true
  sleep 2
done

iface=$(<"$state")
sed "s/^external:.*/external: ${iface}/" /etc/danted.conf.template >/run/danted/danted.conf
exec /usr/sbin/danted -f /run/danted/danted.conf
