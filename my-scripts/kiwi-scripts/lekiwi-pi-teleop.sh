#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  lekiwi-pi-teleop.sh [LEADER_PORT]

Or with environment variables:
  KIWI_LEADER_PORT=/dev/tty.usbmodem5AE60574511 \
  ./my-scripts/kiwi-scripts/lekiwi-pi-teleop.sh

Defaults:
  KIWI_LEADER_PORT=/dev/tty.usbmodem5AE60574511
  KIWI_PI_USER=robot
  KIWI_PI_HOST=pi5-robot.local
  KIWI_PI_REPO_DIR=/home/robot/dev/lerobot
  KIWI_PI_PYTHON=/home/robot/miniforge3/envs/lerobot-fork/bin/python
  KIWI_ROBOT_PORT=/dev/ttyACM0
  KIWI_LOCAL_CONDA_ENV=lerobot-fork
  KIWI_ENABLE_CAMERAS=0
zzzzzzwwwxzzzrwzzzzwwwzwzxxxxwzxxzwwzwzwzw  KIWI_FRONT_CAMERA_PATH=/dev/video0
  KIWI_WRIST_CAMERA_PATH=/dev/video2
  KIWI_CAMERA_FOURCC=MJPG
  KIWI_CAMERA_BACKEND=200
  KIWI_STOP_EXISTING_HOST=1

The Pi must accept key-based SSH from this laptop so the launcher can start and
stop the remote LeKiwi host non-interactively.
EOF
}

shell_quote() {
  printf "%q" "$1"
}

DEFAULT_LEADER_PORT="/dev/tty.usbmodem5AE60574511"
LEADER_PORT="${1:-${KIWI_LEADER_PORT:-$DEFAULT_LEADER_PORT}}"

if [[ -z "$LEADER_PORT" ]]; then
  usage
  exit 2
fi

PI_USER="${KIWI_PI_USER:-robot}"
PI_HOST="${KIWI_PI_HOST:-pi5-robot.local}"
PI_TARGET="${PI_USER}@${PI_HOST}"
PI_REPO_DIR="${KIWI_PI_REPO_DIR:-/home/robot/dev/lerobot}"
PI_PYTHON="${KIWI_PI_PYTHON:-/home/robot/miniforge3/envs/lerobot-fork/bin/python}"

ROBOT_PORT="${KIWI_ROBOT_PORT:-/dev/ttyACM0}"
ROBOT_ID="${KIWI_ROBOT_ID:-my_awesome_kiwi}"
LEADER_ID="${KIWI_LEADER_ID:-my_awesome_leader_arm}"
HOST_TIME_S="${KIWI_HOST_TIME_S:-3600}"
HOST_START_TIMEOUT_S="${KIWI_HOST_START_TIMEOUT_S:-30}"
PORT_ZMQ_CMD="${KIWI_PORT_ZMQ_CMD:-5555}"
PORT_ZMQ_OBSERVATIONS="${KIWI_PORT_ZMQ_OBSERVATIONS:-5556}"
STOP_EXISTING_HOST="${KIWI_STOP_EXISTING_HOST:-1}"
DISABLE_CAMERAS="${KIWI_DISABLE_CAMERAS:-1}"
ENABLE_CAMERAS="${KIWI_ENABLE_CAMERAS:-0}"
LOCAL_CONDA_ENV="${KIWI_LOCAL_CONDA_ENV:-lerobot-fork}"
LOCAL_PYTHON="${KIWI_LOCAL_PYTHON:-}"
CAMERA_FOURCC="${KIWI_CAMERA_FOURCC:-MJPG}"
CAMERA_BACKEND="${KIWI_CAMERA_BACKEND:-200}"

ENABLE_FRONT_CAMERA="${KIWI_ENABLE_FRONT_CAMERA:-1}"
FRONT_CAMERA_NAME="${KIWI_FRONT_CAMERA_NAME:-${KIWI_CAMERA_NAME:-front}}"
FRONT_CAMERA_PATH="${KIWI_FRONT_CAMERA_PATH:-${KIWI_CAMERA_PATH:-/dev/video0}}"
FRONT_CAMERA_WIDTH="${KIWI_FRONT_CAMERA_WIDTH:-${KIWI_CAMERA_WIDTH:-640}}"
FRONT_CAMERA_HEIGHT="${KIWI_FRONT_CAMERA_HEIGHT:-${KIWI_CAMERA_HEIGHT:-480}}"
FRONT_CAMERA_FPS="${KIWI_FRONT_CAMERA_FPS:-${KIWI_CAMERA_FPS:-30}}"
FRONT_CAMERA_FOURCC="${KIWI_FRONT_CAMERA_FOURCC:-$CAMERA_FOURCC}"
FRONT_CAMERA_BACKEND="${KIWI_FRONT_CAMERA_BACKEND:-$CAMERA_BACKEND}"
FRONT_CAMERA_ROTATION="${KIWI_FRONT_CAMERA_ROTATION:-${KIWI_CAMERA_ROTATION:-0}}"
FRONT_CAMERA_WARMUP_S="${KIWI_FRONT_CAMERA_WARMUP_S:-${KIWI_CAMERA_WARMUP_S:-2}}"

ENABLE_WRIST_CAMERA="${KIWI_ENABLE_WRIST_CAMERA:-1}"
WRIST_CAMERA_NAME="${KIWI_WRIST_CAMERA_NAME:-wrist}"
WRIST_CAMERA_PATH="${KIWI_WRIST_CAMERA_PATH:-/dev/video2}"
WRIST_CAMERA_WIDTH="${KIWI_WRIST_CAMERA_WIDTH:-480}"
WRIST_CAMERA_HEIGHT="${KIWI_WRIST_CAMERA_HEIGHT:-640}"
WRIST_CAMERA_FPS="${KIWI_WRIST_CAMERA_FPS:-30}"
WRIST_CAMERA_FOURCC="${KIWI_WRIST_CAMERA_FOURCC:-$CAMERA_FOURCC}"
WRIST_CAMERA_BACKEND="${KIWI_WRIST_CAMERA_BACKEND:-$CAMERA_BACKEND}"
WRIST_CAMERA_ROTATION="${KIWI_WRIST_CAMERA_ROTATION:-90}"
WRIST_CAMERA_WARMUP_S="${KIWI_WRIST_CAMERA_WARMUP_S:-2}"

case "$ENABLE_CAMERAS" in
  1|true|True|TRUE|yes|Yes|YES)
    DISABLE_CAMERAS=0
    ;;
esac

if [[ -n "$LOCAL_PYTHON" ]]; then
  PYTHON_CMD=("$LOCAL_PYTHON")
elif [[ -x "$HOME/miniforge3/envs/$LOCAL_CONDA_ENV/bin/python" ]]; then
  PYTHON_CMD=("$HOME/miniforge3/envs/$LOCAL_CONDA_ENV/bin/python")
elif command -v conda >/dev/null 2>&1 && conda run -n "$LOCAL_CONDA_ENV" python -c 'import zmq' >/dev/null 2>&1; then
  PYTHON_CMD=(conda run -n "$LOCAL_CONDA_ENV" python)
elif command -v uv >/dev/null 2>&1; then
  PYTHON_CMD=(uv run python)
elif command -v python >/dev/null 2>&1; then
  PYTHON_CMD=(python)
else
  PYTHON_CMD=(python3)
fi
export PYTHONPATH="$REPO_ROOT/src${PYTHONPATH:+:$PYTHONPATH}"

if ! "${PYTHON_CMD[@]}" -c 'import zmq' >/dev/null 2>&1; then
  cat >&2 <<EOF
Local Python cannot import pyzmq.

Current local command:
  ${PYTHON_CMD[*]}

Use the prepared conda env or override the local Python:
  KIWI_LOCAL_CONDA_ENV=lerobot-fork ./my-scripts/kiwi-scripts/lekiwi-pi-teleop.sh "$LEADER_PORT"
  KIWI_LOCAL_PYTHON=/Users/rdolgov/miniforge3/envs/lerobot-fork/bin/python ./my-scripts/kiwi-scripts/lekiwi-pi-teleop.sh "$LEADER_PORT"
EOF
  exit 1
fi

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5)

echo "Checking SSH to $PI_TARGET..."
if ! ssh "${SSH_OPTS[@]}" "$PI_TARGET" true; then
  cat >&2 <<EOF
Could not connect non-interactively to $PI_TARGET.

Verify the Pi is reachable:
  ssh $PI_TARGET

Then install key-based SSH for this laptop, for example:
  ssh-copy-id $PI_TARGET

After that, rerun this launcher.
EOF
  exit 1
fi

REMOTE_REPO_DIR="$(shell_quote "$PI_REPO_DIR")"
REMOTE_SRC_DIR="$(shell_quote "$PI_REPO_DIR/src")"
REMOTE_PYTHON="$(shell_quote "$PI_PYTHON")"
REMOTE_ROBOT_ID="$(shell_quote "$ROBOT_ID")"
REMOTE_ROBOT_PORT="$(shell_quote "$ROBOT_PORT")"
REMOTE_HOST_TIME_S="$(shell_quote "$HOST_TIME_S")"
REMOTE_PORT_ZMQ_CMD="$(shell_quote "$PORT_ZMQ_CMD")"
REMOTE_PORT_ZMQ_OBSERVATIONS="$(shell_quote "$PORT_ZMQ_OBSERVATIONS")"

camera_entry() {
  local name="$1"
  local path="$2"
  local width="$3"
  local height="$4"
  local fps="$5"
  local fourcc="$6"
  local backend="$7"
  local rotation="$8"
  local warmup_s="$9"
  printf "%s: {type: opencv, index_or_path: %s, width: %s, height: %s, fps: %s, fourcc: %s, backend: %s, rotation: %s, warmup_s: %s}" \
    "$name" "$path" "$width" "$height" "$fps" "$fourcc" "$backend" "$rotation" "$warmup_s"
}

make_camera_preflight_cmd() {
  local path="$1"
  local width="$2"
  local height="$3"
  local fps="$4"
  local fourcc="$5"
  local backend="$6"
  local remote_path remote_width remote_height remote_fps remote_fourcc remote_backend
  remote_path="$(shell_quote "$path")"
  remote_width="$(shell_quote "$width")"
  remote_height="$(shell_quote "$height")"
  remote_fps="$(shell_quote "$fps")"
  remote_fourcc="$(shell_quote "$fourcc")"
  remote_backend="$(shell_quote "$backend")"
  printf "set -eu; test -e %s; CAMERA_PATH=%s CAMERA_WIDTH=%s CAMERA_HEIGHT=%s CAMERA_FPS=%s CAMERA_FOURCC=%s CAMERA_BACKEND=%s %s -c 'import cv2, os, time; path=os.environ[\"CAMERA_PATH\"]; width=float(os.environ[\"CAMERA_WIDTH\"]); height=float(os.environ[\"CAMERA_HEIGHT\"]); fps=float(os.environ[\"CAMERA_FPS\"]); fourcc=os.environ[\"CAMERA_FOURCC\"]; backend=int(os.environ[\"CAMERA_BACKEND\"]); cap=cv2.VideoCapture(path, backend); cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*fourcc)); cap.set(cv2.CAP_PROP_FRAME_WIDTH, width); cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height); cap.set(cv2.CAP_PROP_FPS, fps); time.sleep(1); ok, frame = cap.read(); cap.release(); assert ok and frame is not None, \"no frame\"; print(f\"camera ok: {path} {frame.shape}\")'" \
    "$remote_path" "$remote_path" "$remote_width" "$remote_height" "$remote_fps" "$remote_fourcc" "$remote_backend" "$REMOTE_PYTHON"
}

camera_enabled() {
  case "$1" in
    1|true|True|TRUE|yes|Yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

REMOTE_CAMERA_ARGS=""
CAMERA_PREFLIGHTS=()
case "$DISABLE_CAMERAS" in
  0|false|False|FALSE|no|No|NO)
    CAMERA_ENTRIES=()
    if camera_enabled "$ENABLE_FRONT_CAMERA"; then
      CAMERA_ENTRIES+=("$(camera_entry "$FRONT_CAMERA_NAME" "$FRONT_CAMERA_PATH" "$FRONT_CAMERA_WIDTH" "$FRONT_CAMERA_HEIGHT" "$FRONT_CAMERA_FPS" "$FRONT_CAMERA_FOURCC" "$FRONT_CAMERA_BACKEND" "$FRONT_CAMERA_ROTATION" "$FRONT_CAMERA_WARMUP_S")")
      CAMERA_PREFLIGHTS+=("$FRONT_CAMERA_NAME|$FRONT_CAMERA_PATH|$FRONT_CAMERA_WIDTH|$FRONT_CAMERA_HEIGHT|$FRONT_CAMERA_FPS|$FRONT_CAMERA_FOURCC|$FRONT_CAMERA_BACKEND")
    fi
    if camera_enabled "$ENABLE_WRIST_CAMERA"; then
      CAMERA_ENTRIES+=("$(camera_entry "$WRIST_CAMERA_NAME" "$WRIST_CAMERA_PATH" "$WRIST_CAMERA_WIDTH" "$WRIST_CAMERA_HEIGHT" "$WRIST_CAMERA_FPS" "$WRIST_CAMERA_FOURCC" "$WRIST_CAMERA_BACKEND" "$WRIST_CAMERA_ROTATION" "$WRIST_CAMERA_WARMUP_S")")
      CAMERA_PREFLIGHTS+=("$WRIST_CAMERA_NAME|$WRIST_CAMERA_PATH|$WRIST_CAMERA_WIDTH|$WRIST_CAMERA_HEIGHT|$WRIST_CAMERA_FPS|$WRIST_CAMERA_FOURCC|$WRIST_CAMERA_BACKEND")
    fi
    if [[ "${#CAMERA_ENTRIES[@]}" -eq 0 ]]; then
      echo "KIWI_ENABLE_CAMERAS is set, but no cameras are enabled." >&2
      exit 2
    fi
    CAMERA_CONFIG="{${CAMERA_ENTRIES[0]}"
    for ((i = 1; i < ${#CAMERA_ENTRIES[@]}; i++)); do
      CAMERA_CONFIG="$CAMERA_CONFIG, ${CAMERA_ENTRIES[$i]}"
    done
    CAMERA_CONFIG="$CAMERA_CONFIG}"
    REMOTE_CAMERA_CONFIG="$(shell_quote "$CAMERA_CONFIG")"
    REMOTE_CAMERA_ARGS=" --robot.cameras=$REMOTE_CAMERA_CONFIG"
    ;;
  *)
    REMOTE_CAMERA_ARGS=" --robot.cameras='{}'"
    ;;
esac

REMOTE_PREFLIGHT_CMD="set -eu; test -d $REMOTE_REPO_DIR; test -x $REMOTE_PYTHON; PYTHONPATH=$REMOTE_SRC_DIR $REMOTE_PYTHON -c 'import lerobot; import zmq'"
REMOTE_FIND_HOSTS_CMD='pgrep -af "lerobot[.]robots[.]lekiwi[.]lekiwi_host" || true'
REMOTE_STOP_HOSTS_CMD='pids=$(pgrep -f "lerobot[.]robots[.]lekiwi[.]lekiwi_host" || true); if [ -n "$pids" ]; then echo "Stopping existing LeKiwi host PIDs: $pids"; kill $pids; sleep 1; fi'
REMOTE_CMD="set -eu; cd $REMOTE_REPO_DIR; printf '\\n' | PYTHONPATH=$REMOTE_SRC_DIR $REMOTE_PYTHON -m lerobot.robots.lekiwi.lekiwi_host --robot.id=$REMOTE_ROBOT_ID --robot.port=$REMOTE_ROBOT_PORT$REMOTE_CAMERA_ARGS --host.connection_time_s=$REMOTE_HOST_TIME_S --host.port_zmq_cmd=$REMOTE_PORT_ZMQ_CMD --host.port_zmq_observations=$REMOTE_PORT_ZMQ_OBSERVATIONS"

HOST_SSH_PID=""

cleanup() {
  status=$?
  if [[ -n "$HOST_SSH_PID" ]] && kill -0 "$HOST_SSH_PID" 2>/dev/null; then
    echo
    echo "Stopping remote LeKiwi host..."
    kill "$HOST_SSH_PID" 2>/dev/null || true
    wait "$HOST_SSH_PID" 2>/dev/null || true
  fi
  exit "$status"
}

trap cleanup EXIT INT TERM

cd "$REPO_ROOT"

echo "Checking Pi repo and Python environment..."
if ! ssh "${SSH_OPTS[@]}" "$PI_TARGET" "$REMOTE_PREFLIGHT_CMD"; then
  cat >&2 <<EOF
Pi preflight failed.

Expected repo:
  $PI_REPO_DIR

Expected Python:
  $PI_PYTHON

Override these if your Pi uses different paths:
  KIWI_PI_REPO_DIR=/path/to/lerobot
  KIWI_PI_PYTHON=/path/to/python
EOF
  exit 1
fi

existing_hosts="$(ssh "${SSH_OPTS[@]}" "$PI_TARGET" "$REMOTE_FIND_HOSTS_CMD")"
if [[ -n "$existing_hosts" ]]; then
  case "$STOP_EXISTING_HOST" in
    1|true|True|TRUE|yes|Yes|YES)
      echo "Existing LeKiwi host found on $PI_TARGET:"
      echo "$existing_hosts"
      ssh "${SSH_OPTS[@]}" "$PI_TARGET" "$REMOTE_STOP_HOSTS_CMD"
      ;;
    *)
      cat >&2 <<EOF
An existing LeKiwi host is already running on $PI_TARGET:
$existing_hosts

Stop it first, or let this launcher stop stale hosts automatically:
  KIWI_STOP_EXISTING_HOST=1 ./my-scripts/kiwi-scripts/lekiwi-pi-teleop.sh
EOF
      exit 1
      ;;
  esac
fi

case "$DISABLE_CAMERAS" in
  0|false|False|FALSE|no|No|NO)
    for camera_spec in "${CAMERA_PREFLIGHTS[@]}"; do
      IFS="|" read -r camera_name camera_path camera_width camera_height camera_fps camera_fourcc camera_backend <<<"$camera_spec"
      echo "Checking Pi camera '$camera_name' at $camera_path with backend $camera_backend and fourcc $camera_fourcc..."
      remote_camera_preflight_cmd="$(make_camera_preflight_cmd "$camera_path" "$camera_width" "$camera_height" "$camera_fps" "$camera_fourcc" "$camera_backend")"
      if ! ssh "${SSH_OPTS[@]}" "$PI_TARGET" "$remote_camera_preflight_cmd"; then
        remote_camera_path="$(shell_quote "$camera_path")"
        ssh "${SSH_OPTS[@]}" "$PI_TARGET" "fuser -v $remote_camera_path 2>&1 || true; pgrep -af 'lerobot[.]robots[.]lekiwi[.]lekiwi_host' || true" >&2 || true
        cat >&2 <<EOF
Pi camera preflight failed.

Current camera config:
  name:    $camera_name
  path:    $camera_path
  width:   $camera_width
  height:  $camera_height
  fps:     $camera_fps
  fourcc:  $camera_fourcc
  backend: $camera_backend

Check devices:
  ssh $PI_TARGET 'v4l2-ctl --list-devices'
  ssh $PI_TARGET 'v4l2-ctl --device=$camera_path --list-formats-ext'
  ssh $PI_TARGET 'fuser -v $camera_path'

Or run without cameras:
  KIWI_ENABLE_CAMERAS=0 ./my-scripts/kiwi-scripts/lekiwi-pi-teleop.sh
EOF
        exit 1
      fi
    done
    ;;
esac

echo "Starting LeKiwi host on $PI_TARGET using robot port $ROBOT_PORT..."
ssh "${SSH_OPTS[@]}" "$PI_TARGET" "$REMOTE_CMD" &
HOST_SSH_PID=$!

sleep 1
if ! kill -0 "$HOST_SSH_PID" 2>/dev/null; then
  wait "$HOST_SSH_PID" 2>/dev/null || true
  echo "Remote LeKiwi host exited before opening ports. Check the SSH host output above." >&2
  exit 1
fi

echo "Waiting for LeKiwi host ports $PORT_ZMQ_CMD and $PORT_ZMQ_OBSERVATIONS on $PI_HOST..."
"${PYTHON_CMD[@]}" - "$PI_HOST" "$PORT_ZMQ_CMD" "$PORT_ZMQ_OBSERVATIONS" "$HOST_START_TIMEOUT_S" <<'PY'
import socket
import sys
import time

host = sys.argv[1]
ports = tuple(int(arg) for arg in sys.argv[2:4])
timeout_s = float(sys.argv[4])
deadline = time.time() + timeout_s

while time.time() < deadline:
    ok = True
    for port in ports:
        try:
            with socket.create_connection((host, port), timeout=0.5):
                pass
        except OSError:
            ok = False
            break
    if ok:
        sys.exit(0)
    time.sleep(0.2)

print(f"Timed out waiting for LeKiwi host ports {ports} on {host}. Check the SSH host output above.", file=sys.stderr)
sys.exit(1)
PY

if ! kill -0 "$HOST_SSH_PID" 2>/dev/null; then
  wait "$HOST_SSH_PID" 2>/dev/null || true
  echo "Remote LeKiwi host exited before teleop started. Check the SSH host output above." >&2
  exit 1
fi

echo "Starting teleoperation client with leader arm on $LEADER_PORT..."
echo "If prompted for leader calibration, press ENTER to use the saved file or type c to recalibrate."

LEKIWI_REMOTE_IP="$PI_HOST" \
LEKIWI_PORT_ZMQ_CMD="$PORT_ZMQ_CMD" \
LEKIWI_PORT_ZMQ_OBSERVATIONS="$PORT_ZMQ_OBSERVATIONS" \
LEKIWI_ROBOT_ID="$ROBOT_ID" \
LEKIWI_LEADER_PORT="$LEADER_PORT" \
LEKIWI_LEADER_ID="$LEADER_ID" \
LEKIWI_DISABLE_CAMERAS="$DISABLE_CAMERAS" \
  "${PYTHON_CMD[@]}" examples/lekiwi/teleoperate.py
