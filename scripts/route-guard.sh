#!/usr/bin/env bash
set -euo pipefail

delete_guard_table() {
  nft delete table inet hillstone_guard 2>/dev/null || true
}

apply_locked_rules() {
  delete_guard_table
  nft -f - <<'NFT'
table inet hillstone_guard {
  chain output {
    type filter hook output priority -10; policy accept;
    meta skuid socksproxy oifname "lo" accept
    meta skuid socksproxy ct state established,related accept
    meta skuid socksproxy reject
  }
}
NFT
}

apply_vpn_rules() {
  local iface=$1
  local cidrs=${SOCKS_ALLOWED_CIDRS:-}
  if [[ ! "$cidrs" =~ ^[0-9./]+(,[0-9./]+)*$ ]]; then
    echo "Invalid SOCKS_ALLOWED_CIDRS: $cidrs" >&2
    return 1
  fi
  local allow_rules=
  local cidr
  IFS=',' read -ra cidr_list <<<"$cidrs"
  for cidr in "${cidr_list[@]}"; do
    allow_rules+="    tcp dport 1080 ip saddr $cidr accept"$'\n'
  done
  delete_guard_table
  nft -f - <<NFT
table inet hillstone_guard {
  chain input {
    type filter hook input priority -10; policy accept;
${allow_rules}    tcp dport 1080 reject
  }
  chain output {
    type filter hook output priority -10; policy accept;
    meta skuid socksproxy oifname "lo" accept
    meta skuid socksproxy ct state established,related accept
    meta skuid socksproxy oifname "$iface" accept
    meta skuid socksproxy reject
  }
}
NFT
}

apply_locked_rules
last_iface=

while true; do
  if iface=$(/usr/local/bin/detect-vpn-interface.sh 2>/dev/null); then
    if [[ "$iface" != "$last_iface" ]]; then
      if apply_vpn_rules "$iface"; then
        if supervisorctl restart socks >/dev/null 2>&1; then
          last_iface=$iface
          echo "VPN guard opened SOCKS egress on $iface"
        else
          echo "Failed to restart SOCKS; keeping egress locked" >&2
          apply_locked_rules
          supervisorctl restart socks >/dev/null 2>&1 || true
          last_iface=
        fi
      else
        apply_locked_rules
        last_iface=
      fi
    fi
  elif [[ -n "$last_iface" ]] || [[ -s /run/hillstone-vpn/interface ]]; then
    apply_locked_rules
    rm -f /run/hillstone-vpn/interface
    supervisorctl restart socks >/dev/null 2>&1 || true
    last_iface=
    echo "VPN guard locked SOCKS egress"
  fi
  sleep 2
done
