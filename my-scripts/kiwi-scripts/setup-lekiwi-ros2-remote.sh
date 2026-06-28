#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE="${LEKIWI_REMOTE:-robot@pi3-robot.local}"
REMOTE_SCRIPT="/tmp/setup-lekiwi-ros2-pi.sh"

cat <<EOF
Setting up LeKiwi ROS2 on:
  $REMOTE

This copies the local bootstrap script to the remote machine and runs it there.
EOF

scp "$SCRIPT_DIR/setup-lekiwi-ros2-pi.sh" "$REMOTE:$REMOTE_SCRIPT"
ssh "$REMOTE" "chmod +x '$REMOTE_SCRIPT' && '$REMOTE_SCRIPT'"
