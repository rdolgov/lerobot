#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

cd "${LEKIWI_ROS_WS}"
python -m colcon build --symlink-install --packages-select lekiwi_ros_bridge

echo
echo "Build complete. Source the workspace with:"
echo "  source ${LEKIWI_ROS_WS}/install/setup.bash"

