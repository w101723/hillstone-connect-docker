#!/usr/bin/env bash
set -euo pipefail

flwm &
wm_pid=$!

for _ in $(seq 1 60); do
  if [[ -s /run/hillstone-vpn/service-ready ]] && \
     ss -lnt | grep -qE '127\.0\.0\.1:35421\b'; then
    break
  fi
  sleep 1
done

if [[ ! -s /run/hillstone-vpn/service-ready ]]; then
  echo "Hillstone service was not ready before GUI startup" >&2
  xterm -title "Hillstone service unavailable" -e bash -lc \
    "echo 'Hillstone service is not listening on 127.0.0.1:35421'; exec bash" &
  wait "$wm_pid"
  exit 1
fi

export LANG=${LANG:-zh_CN.UTF-8}
export LANGUAGE=${LANGUAGE:-zh_CN:zh}
export LC_ALL=${LC_ALL:-zh_CN.UTF-8}

hillstone_config_dir=${HOME}/.config/HillstoneSecureConnect
hillstone_config=${hillstone_config_dir}/AppConfig.ini
auto_minimize=${HILLSTONE_AUTO_MINIMIZE:-false}

if [[ "$auto_minimize" != "true" && "$auto_minimize" != "false" ]]; then
  echo "Invalid HILLSTONE_AUTO_MINIMIZE: $auto_minimize" >&2
  exit 1
fi

install -d "$hillstone_config_dir"
if [[ -f "$hillstone_config" ]]; then
  if grep -q '^AutoMinimize=' "$hillstone_config"; then
    sed -i "s/^AutoMinimize=.*/AutoMinimize=${auto_minimize}/" "$hillstone_config"
  elif grep -q '^\[General\]$' "$hillstone_config"; then
    sed -i "/^\[General\]$/a AutoMinimize=${auto_minimize}" "$hillstone_config"
  else
    printf '\n[General]\nAutoMinimize=%s\n' "$auto_minimize" >>"$hillstone_config"
  fi
else
  printf '[General]\nAutoMinimize=%s\n' "$auto_minimize" >"$hillstone_config"
fi

gui_command=${HILLSTONE_GUI_COMMAND:-${HILLSTONE_HOME}/bin/HillstoneSecureConnect.sh}
echo "Starting Hillstone GUI: $gui_command"
bash -lc "$gui_command" &
gui_pid=$!

set +e
wait "$gui_pid"
gui_status=$?
set -e
echo "Hillstone GUI exited with status $gui_status" >&2

xterm -title "Hillstone diagnostics (GUI exit $gui_status)" \
  -e bash -lc "echo 'Hillstone GUI exited with status $gui_status'; echo 'Run: $gui_command'; exec bash" &

wait "$wm_pid"
