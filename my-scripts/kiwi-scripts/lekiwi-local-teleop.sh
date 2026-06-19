#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  lekiwi-local-teleop.sh ROBOT_PORT LEADER_PORT

Or with environment variables:
  KIWI_ROBOT_PORT=/dev/tty.usbmodem5B610338241 \
  KIWI_LEADER_PORT=/dev/tty.usbmodem5AE60574511 \
  ./my-scripts/kiwi-scripts/lekiwi-local-teleop.sh

The robot port is the LeKiwi base/follower motor board.
The leader port is the separate SO100/SO101 leader arm board.
EOF
}

ROBOT_PORT="${1:-${KIWI_ROBOT_PORT:-}}"
LEADER_PORT="${2:-${KIWI_LEADER_PORT:-}}"

if [[ -z "$ROBOT_PORT" || -z "$LEADER_PORT" ]]; then
  usage
  exit 2
fi

ROBOT_ID="${KIWI_ROBOT_ID:-my_awesome_kiwi}"
LEADER_ID="${KIWI_LEADER_ID:-my_awesome_leader_arm}"
HOST_TIME_S="${KIWI_HOST_TIME_S:-3600}"
HOST_START_TIMEOUT_S="${KIWI_HOST_START_TIMEOUT_S:-30}"

if [[ "$ROBOT_PORT" == "$LEADER_PORT" ]]; then
  echo "Robot port and leader port must be different:"
  echo "  robot:  $ROBOT_PORT"
  echo "  leader: $LEADER_PORT"
  exit 2
fi

if command -v uv >/dev/null 2>&1; then
  PYTHON_CMD=(uv run python)
elif command -v python >/dev/null 2>&1; then
  PYTHON_CMD=(python)
  export PYTHONPATH="$REPO_ROOT/src${PYTHONPATH:+:$PYTHONPATH}"
else
  PYTHON_CMD=(python3)
  export PYTHONPATH="$REPO_ROOT/src${PYTHONPATH:+:$PYTHONPATH}"
fi

HOST_PID=""

cleanup() {
  status=$?
  if [[ -n "$HOST_PID" ]] && kill -0 "$HOST_PID" 2>/dev/null; then
    echo
    echo "Stopping LeKiwi host..."
    kill "$HOST_PID" 2>/dev/null || true
    wait "$HOST_PID" 2>/dev/null || true
  fi
  exit "$status"
}

trap cleanup EXIT INT TERM

cd "$REPO_ROOT"

echo "Starting LeKiwi host on $ROBOT_PORT..."
echo "Using robot id '$ROBOT_ID'. Cameras are disabled for local wired smoke tests."

# Send one newline so an existing robot calibration file is accepted automatically.
# If the robot has not been calibrated yet, run lerobot-calibrate before this script.
printf '\n' | "${PYTHON_CMD[@]}" -m lerobot.robots.lekiwi.lekiwi_host \
  --robot.id="$ROBOT_ID" \
  --robot.port="$ROBOT_PORT" \
  --robot.cameras='{}' \
  --host.connection_time_s="$HOST_TIME_S" &
HOST_PID=$!

echo "Waiting for LeKiwi host ports 5555 and 5556..."
"${PYTHON_CMD[@]}" - "$HOST_START_TIMEOUT_S" <<'PY'
import socket
import sys
import time

timeout_s = float(sys.argv[1])
deadline = time.time() + timeout_s
ports = (5555, 5556)

while time.time() < deadline:
    ok = True
    for port in ports:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                pass
        except OSError:
            ok = False
            break
    if ok:
        sys.exit(0)
    time.sleep(0.2)

print(f"Timed out waiting for LeKiwi host ports {ports}. Check the host output above.", file=sys.stderr)
sys.exit(1)
PY

echo "Starting teleoperation client with leader arm on $LEADER_PORT..."
echo "If prompted for leader calibration, press ENTER to use the saved file or type c to recalibrate."

LEKIWI_REMOTE_IP=127.0.0.1 \
LEKIWI_ROBOT_ID="$ROBOT_ID" \
LEKIWI_LEADER_PORT="$LEADER_PORT" \
LEKIWI_LEADER_ID="$LEADER_ID" \
LEKIWI_DISABLE_CAMERAS=1 \
  "${PYTHON_CMD[@]}" examples/lekiwi/teleoperate.py
