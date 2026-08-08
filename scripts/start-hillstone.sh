#!/usr/bin/env bash
set -euo pipefail

export HOME=/home/desktop
export DISPLAY=${DISPLAY:-:1}
export XDG_RUNTIME_DIR=/run/user/$(id -u)

if [[ -n "${HILLSTONE_DAEMON_COMMAND:-}" ]]; then
  bash -lc "$HILLSTONE_DAEMON_COMMAND" &
fi

while [[ ! -S /tmp/.X11-unix/X1 ]]; do sleep 1; done

command=${HILLSTONE_GUI_COMMAND:-/opt/HillstoneSecureConnect/bin/HillstoneSecureConnect}
while [[ ! -x "${command%% *}" ]]; do
  echo "Waiting for Hillstone GUI installation at: $command" >&2
  sleep 5
done

while [[ ! -x /opt/HillstoneSecureConnect/bin/HillstoneSecureConnectService ]]; do sleep 2; done
exec bash -lc "$command"
