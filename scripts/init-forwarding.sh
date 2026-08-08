#!/usr/bin/env bash
set -euo pipefail

if [[ $(< /proc/sys/net/ipv4/ip_forward) != 1 ]]; then
  if ! sysctl -q -w net.ipv4.ip_forward=1; then
    echo "ERROR: IPv4 forwarding is disabled; start the container with --sysctl net.ipv4.ip_forward=1" >&2
    exit 1
  fi
fi

iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

if ! iptables -t nat -C POSTROUTING -j MASQUERADE 2>/dev/null; then
  iptables -t nat -A POSTROUTING -j MASQUERADE
fi

iptables -t nat -C POSTROUTING -j MASQUERADE
