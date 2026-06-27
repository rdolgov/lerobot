#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

MOCK="${MOCK:-false}"
ROBOT_ID="${ROBOT_ID:-my_awesome_kiwi}"
LEKIWI_PORT="${LEKIWI_PORT:-/dev/ttyACM0}"
DISABLE_CAMERAS="${DISABLE_CAMERAS:-true}"
MAX_LOOP_FREQ_HZ="${MAX_LOOP_FREQ_HZ:-30.0}"
WATCHDOG_TIMEOUT_MS="${WATCHDOG_TIMEOUT_MS:-500.0}"

exec ros2 run lekiwi_ros_bridge lekiwi_host_node --ros-args \
  -p mock:="${MOCK}" \
  -p robot_id:="${ROBOT_ID}" \
  -p port:="${LEKIWI_PORT}" \
  -p disable_cameras:="${DISABLE_CAMERAS}" \
  -p max_loop_freq_hz:="${MAX_LOOP_FREQ_HZ}" \
  -p watchdog_timeout_ms:="${WATCHDOG_TIMEOUT_MS}"

