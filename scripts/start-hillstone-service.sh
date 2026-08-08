#!/usr/bin/env bash
set -euo pipefail

service=${HILLSTONE_SERVICE_COMMAND:-${HILLSTONE_HOME}/bin/HillstoneSecureConnectService}
ready=/run/hillstone-vpn/service-ready
service_pattern="^${service//./\\.}([[:space:]]|$)"
rm -f "$ready"

pkill -9 -f "$service_pattern" 2>/dev/null || true
sleep 1
"$service"

pid=
for _ in $(seq 1 30); do
  pid=$(pgrep -fo "$service_pattern" 2>/dev/null || true)
  if [[ -n "$pid" ]] && ss -lntp | grep -qE '127\.0\.0\.1:35421\b.*HillstoneSecure'; then
    printf '%s\n' "$pid" >"${ready}.tmp"
    mv "${ready}.tmp" "$ready"
    break
  fi
  sleep 1
done

if [[ ! -s "$ready" ]]; then
  echo "Hillstone service failed to listen on 127.0.0.1:35421" >&2
  pgrep -af "$service_pattern" >&2 || true
  ss -lntp >&2 || true
  exit 1
fi

cleanup() {
  rm -f "$ready"
}
trap cleanup EXIT INT TERM

while kill -0 "$pid" 2>/dev/null; do
  if ! ss -lntp | grep -qE '127\.0\.0\.1:35421\b.*HillstoneSecure'; then
    echo "Hillstone service listener disappeared" >&2
    exit 1
  fi
  sleep 2
done

exit 1
