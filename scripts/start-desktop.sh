#!/usr/bin/env bash
set -euo pipefail

export HOME=/home/desktop
mkdir -p "$HOME/.vnc"

cat >"$HOME/.vnc/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_RUNTIME_DIR=/run/user/$(id -u)
exec dbus-run-session -- /usr/local/bin/start-desktop-session.sh
EOF
chmod 0755 "$HOME/.vnc/xstartup"

vncserver -kill :1 >/dev/null 2>&1 || true
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
exec vncserver :1 -fg -localhost yes -SecurityTypes None \
  -geometry "${VNC_GEOMETRY:-1440x900}" -depth "${VNC_DEPTH:-24}"
