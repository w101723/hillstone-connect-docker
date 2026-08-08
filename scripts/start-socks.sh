#!/usr/bin/env bash
set -euo pipefail

exec /usr/local/bin/gost -L socks5://0.0.0.0:1080
