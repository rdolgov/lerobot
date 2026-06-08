#!/usr/bin/env bash
set -euo pipefail

echo "This runs the full LeKiwi setup path for arm + wheels."
echo "For wheel-only setup, run ./my-scripts/kiwi-scripts/kiwi-wheel-setup.sh instead."
read -r -p "Type ALL to continue with full LeKiwi setup: " CONFIRM
if [[ "$CONFIRM" != "ALL" ]]; then
  echo "Cancelled."
  exit 1
fi

lerobot-setup-motors \
  --robot.type=lekiwi \
  --robot.port=/dev/tty.usbmodem5B610338241
