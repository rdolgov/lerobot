#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

RATE_HZ="${RATE_HZ:-5.0}"
X_VEL="${X_VEL:-0.0}"
Y_VEL="${Y_VEL:-0.0}"
THETA_VEL="${THETA_VEL:-0.0}"

exec ros2 run lekiwi_ros_bridge action_publisher --ros-args \
  -p rate_hz:="${RATE_HZ}" \
  -p x_vel:="${X_VEL}" \
  -p y_vel:="${Y_VEL}" \
  -p theta_vel:="${THETA_VEL}"

