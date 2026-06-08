#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 && -z "${KIWI_PORT:-}" ]]; then
  echo "Usage: $0 /dev/tty.usbmodemXXXX"
  echo "   or: KIWI_PORT=/dev/tty.usbmodemXXXX $0"
  exit 2
fi

PORT="${1:-$KIWI_PORT}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if command -v uv >/dev/null 2>&1; then
  cd "$REPO_ROOT"
  uv run python "$SCRIPT_DIR/kiwi-wheel-only.py" setup --port "$PORT"
elif command -v python >/dev/null 2>&1; then
  PYTHONPATH="$REPO_ROOT/src${PYTHONPATH:+:$PYTHONPATH}" python "$SCRIPT_DIR/kiwi-wheel-only.py" setup --port "$PORT"
else
  PYTHONPATH="$REPO_ROOT/src${PYTHONPATH:+:$PYTHONPATH}" python3 "$SCRIPT_DIR/kiwi-wheel-only.py" setup --port "$PORT"
fi
