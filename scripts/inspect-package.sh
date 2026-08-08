#!/usr/bin/env bash
set -euo pipefail

installer=${1:-vendor/HillstoneSecureConnect.run}
[[ -f "$installer" ]] || { echo "missing: $installer" >&2; exit 1; }

file "$installer"
printf 'MD5:    '; md5sum "$installer" | awk '{print $1}'
printf 'SHA256: '; sha256sum "$installer" | awk '{print $1}'

strings "$installer" | grep -Ei '/opt/Hillstone|postinst|postrm|systemd|systemctl|dbus|polkit|pkexec|HillstoneSecureConnect' | sort -u || true
