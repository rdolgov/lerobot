#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_NAME="${SESSION_NAME:-lekiwi_ros}"

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux is not installed. Run the terminal scripts manually instead:" >&2
  echo "  ${SCRIPT_DIR}/terminal1_host.sh" >&2
  echo "  ${SCRIPT_DIR}/terminal2_action_publisher.sh" >&2
  echo "  ${SCRIPT_DIR}/terminal3_observation_echo.sh" >&2
  exit 1
fi

if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
  echo "tmux session already exists: ${SESSION_NAME}" >&2
  echo "Attach with: tmux attach -t ${SESSION_NAME}" >&2
  exit 1
fi

tmux new-session -d -s "${SESSION_NAME}" -n host "${SCRIPT_DIR}/terminal1_host.sh"
tmux split-window -h -t "${SESSION_NAME}:host" "${SCRIPT_DIR}/terminal2_action_publisher.sh"
tmux split-window -v -t "${SESSION_NAME}:host.1" "${SCRIPT_DIR}/terminal3_observation_echo.sh"
tmux select-layout -t "${SESSION_NAME}:host" tiled
tmux attach -t "${SESSION_NAME}"
