#!/usr/bin/env bash
set -euo pipefail

install -d /run/dbus /run/hillstone-vpn /run/danted /home/desktop/.vnc /home/desktop/Desktop
install -d -m 1777 /tmp/.X11-unix
install -d -m 0700 -o desktop -g desktop /run/user/$(id -u desktop)
chown -R desktop:desktop /home/desktop/.vnc /home/desktop/.config
chown socksproxy:socksproxy /run/danted

if [[ ! -c /dev/net/tun ]]; then
  echo "ERROR: /dev/net/tun is unavailable" >&2
  exit 1
fi

for file in /certs/tls.crt /certs/tls.key /certs/htpasswd; do
  if [[ ! -s "$file" ]]; then
    echo "ERROR: missing $file" >&2
    exit 1
  fi
done

if [[ "${LANG:-}" != "zh_CN.UTF-8" ]] || ! locale -a | grep -qi '^zh_CN\.utf8$'; then
  echo "ERROR: zh_CN.UTF-8 locale is unavailable" >&2
  exit 1
fi

if [[ ! -x "${HILLSTONE_HOME}/bin/HillstoneSecureConnect" ]] ||
   [[ ! -x "${HILLSTONE_HOME}/bin/HillstoneSecureConnectService" ]] ||
   [[ ! -x "${HILLSTONE_HOME}/bin/HillstoneSecureConnect.sh" ]]; then
  echo "ERROR: Hillstone client is missing from the built image" >&2
  exit 1
fi

rm -f /etc/nginx/sites-enabled/default
cp /etc/nginx/templates/default.conf.template /etc/nginx/conf.d/default.conf

exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
