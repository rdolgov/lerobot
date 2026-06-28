#!/usr/bin/env bash
set -euo pipefail

HOSTS=("$@")
if [[ "${#HOSTS[@]}" -eq 0 ]]; then
  HOSTS=(robot@pi3-robot.local robot@pi5-robot.local)
fi

for host in "${HOSTS[@]}"; do
  echo
  echo "==> Updating ROS2 LeKiwi environment on $host"
  ssh "$host" 'bash -s' <<'REMOTE'
set -euo pipefail

cat > "$HOME/ros2_lekiwi_env.sh" <<'ENV'
# Common LeKiwi ROS2 environment.
# Source this in every terminal before running ROS2 nodes or CLI commands.

export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-23}"
unset ROS_LOCALHOST_ONLY

source_lekiwi_file() {
  # ROS setup files may read unset variables, so do not source them with
  # `set -u`/nounset enabled.
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "warning: $file not found" >&2
    return 0
  fi

  case "$-" in
    *u*)
      set +u
      source "$file"
      set -u
      ;;
    *)
      source "$file"
      ;;
  esac
}

if [ -f /opt/ros/jazzy/setup.bash ]; then
  source_lekiwi_file /opt/ros/jazzy/setup.bash
else
  echo "warning: /opt/ros/jazzy/setup.bash not found" >&2
fi

if [ -f "$HOME/ros2_lerobot_venv/bin/activate" ]; then
  source_lekiwi_file "$HOME/ros2_lerobot_venv/bin/activate"
else
  echo "warning: $HOME/ros2_lerobot_venv/bin/activate not found" >&2
fi

if [ -f "$HOME/ros2_ws/install/setup.bash" ]; then
  source_lekiwi_file "$HOME/ros2_ws/install/setup.bash"
else
  echo "warning: $HOME/ros2_ws/install/setup.bash not found" >&2
fi

# Keep the default ROS middleware unless you explicitly choose one.
# To force Cyclone DDS later, install ros-jazzy-rmw-cyclonedds-cpp and uncomment:
# export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
ENV

chmod +x "$HOME/ros2_lekiwi_env.sh"

if ! grep -q "BEGIN LeKiwi ROS2 env" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'BASHRC'

# BEGIN LeKiwi ROS2 env
if [ -f "$HOME/ros2_lekiwi_env.sh" ]; then
  source "$HOME/ros2_lekiwi_env.sh"
fi
# END LeKiwi ROS2 env
BASHRC
fi

source "$HOME/ros2_lekiwi_env.sh"
echo "HOST=$(hostname)"
echo "ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-unset}"
echo "ROS_LOCALHOST_ONLY=${ROS_LOCALHOST_ONLY:-unset}"
echo "RMW_IMPLEMENTATION=${RMW_IMPLEMENTATION:-unset}"
echo "PYTHON=$(command -v python || true)"
python -c "import rclpy; print('rclpy ok')" || true
REMOTE
done
