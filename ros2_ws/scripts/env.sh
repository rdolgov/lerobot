#!/usr/bin/env bash

set -e

case $- in
  *u*) LEKIWI_RESTORE_NOUNSET=1 ;;
  *) LEKIWI_RESTORE_NOUNSET=0 ;;
esac
set +u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ROS_DISTRO="${ROS_DISTRO:-jazzy}"
ROS_SETUP="/opt/ros/${ROS_DISTRO}/setup.bash"
LEROBOT_VENV="${LEROBOT_VENV:-${HOME}/ros2_lerobot_venv}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-23}"

if [ ! -f "${ROS_SETUP}" ]; then
  echo "ROS setup file not found: ${ROS_SETUP}" >&2
  return 1 2>/dev/null || exit 1
fi

source "${ROS_SETUP}"

if [ ! -f "${LEROBOT_VENV}/bin/activate" ]; then
  echo "LeRobot virtualenv not found: ${LEROBOT_VENV}" >&2
  return 1 2>/dev/null || exit 1
fi

source "${LEROBOT_VENV}/bin/activate"

if [ -f "${WS_DIR}/install/setup.bash" ]; then
  source "${WS_DIR}/install/setup.bash"
fi

export LEKIWI_ROS_WS="${WS_DIR}"

if [ "${LEKIWI_RESTORE_NOUNSET}" = "1" ]; then
  set -u
fi
unset LEKIWI_RESTORE_NOUNSET
