#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${LEKIWI_REPO_URL:-https://github.com/rdolgov/lerobot.git}"
REPO_BRANCH="${LEKIWI_REPO_BRANCH:-dev}"
REPO_DIR="${LEKIWI_REPO_DIR:-$HOME/dev/fork/rdolgov/lerobot}"
VENV_DIR="${LEKIWI_ROS2_VENV_DIR:-$HOME/ros2_lerobot_venv}"
ROS_WS="${LEKIWI_ROS2_WS:-$HOME/ros2_ws}"
ROS_DISTRO_NAME="${ROS_DISTRO_NAME:-jazzy}"

log() {
  printf '\n==> %s\n' "$*"
}

require_ubuntu_2404_arm64() {
  if [[ ! -f /etc/os-release ]]; then
    echo "This setup script expects Ubuntu 24.04 for ROS2 Jazzy apt packages." >&2
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  local codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  local arch
  arch="$(dpkg --print-architecture)"

  if [[ "$codename" != "noble" ]]; then
    cat >&2 <<EOF
Expected Ubuntu 24.04 (noble), got codename '$codename'.
ROS2 Jazzy apt packages are targeted at Ubuntu 24.04.
EOF
    exit 1
  fi

  case "$arch" in
    arm64|amd64)
      ;;
    *)
      cat >&2 <<EOF
Expected a 64-bit OS architecture (arm64 or amd64), got '$arch'.
For Raspberry Pi 3, install the 64-bit Ubuntu Server 24.04 image.
EOF
      exit 1
      ;;
  esac
}

install_ros2_jazzy() {
  if command -v ros2 >/dev/null 2>&1 && [[ -f "/opt/ros/$ROS_DISTRO_NAME/setup.bash" ]]; then
    log "ROS2 $ROS_DISTRO_NAME already appears to be installed"
    sudo apt update
    sudo apt install -y "ros-$ROS_DISTRO_NAME-rclpy" "ros-$ROS_DISTRO_NAME-sensor-msgs"
    return
  fi

  log "Installing ROS2 $ROS_DISTRO_NAME base packages"
  sudo apt update
  sudo apt install -y software-properties-common curl git python3.12-venv
  sudo add-apt-repository -y universe

  local ros_apt_source_version
  ros_apt_source_version="$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
    | grep -F "tag_name" \
    | awk -F'"' '{print $4}')"

  if [[ -z "$ros_apt_source_version" ]]; then
    echo "Could not determine latest ros-apt-source release." >&2
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  local codename="${UBUNTU_CODENAME:-${VERSION_CODENAME}}"
  local deb="/tmp/ros2-apt-source.deb"
  curl -L -o "$deb" \
    "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ros_apt_source_version}/ros2-apt-source_${ros_apt_source_version}.${codename}_all.deb"
  sudo dpkg -i "$deb"
  sudo apt update
  sudo apt install -y \
    "ros-$ROS_DISTRO_NAME-ros-base" \
    "ros-$ROS_DISTRO_NAME-rclpy" \
    "ros-$ROS_DISTRO_NAME-sensor-msgs" \
    ros-dev-tools
}

clone_or_update_lerobot() {
  log "Preparing LeRobot checkout at $REPO_DIR"
  mkdir -p "$(dirname "$REPO_DIR")"

  if [[ ! -d "$REPO_DIR/.git" ]]; then
    git clone --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
    return
  fi

  cd "$REPO_DIR"
  git remote set-url origin "$REPO_URL"
  git fetch origin "$REPO_BRANCH"

  if [[ -n "$(git status --porcelain)" ]]; then
    cat <<EOF
LeRobot checkout has local changes. Leaving it untouched:
  $REPO_DIR

To update manually:
  cd "$REPO_DIR"
  git status
  git pull --ff-only origin "$REPO_BRANCH"
EOF
    return
  fi

  git checkout "$REPO_BRANCH"
  git pull --ff-only origin "$REPO_BRANCH"
}

create_lerobot_venv() {
  log "Creating ROS2-compatible LeRobot venv at $VENV_DIR"
  /usr/bin/python3.12 -m venv --system-site-packages "$VENV_DIR"

  # shellcheck disable=SC1091
  source "/opt/ros/$ROS_DISTRO_NAME/setup.bash"
  # shellcheck disable=SC1091
  source "$VENV_DIR/bin/activate"

  python -m pip install --upgrade pip
  cd "$REPO_DIR"
  python -m pip install -e ".[lekiwi]"
  python -m pip install "setuptools>=71,<80" cffi websockets
  python -c "import rclpy; import lerobot; print('ROS2 and LeRobot imports work')"
  python -m pip check || true
}

write_bridge_package() {
  log "Writing lekiwi_ros_bridge package into $ROS_WS"
  local pkg_dir="$ROS_WS/src/lekiwi_ros_bridge"
  mkdir -p "$pkg_dir/lekiwi_ros_bridge" "$pkg_dir/resource"

  touch "$pkg_dir/resource/lekiwi_ros_bridge"
  touch "$pkg_dir/lekiwi_ros_bridge/__init__.py"

  cat > "$pkg_dir/package.xml" <<'XML'
<?xml version="1.0"?>
<package format="3">
  <name>lekiwi_ros_bridge</name>
  <version>0.0.1</version>
  <description>Milestone 1 ROS2 bridge for LeKiwi</description>
  <maintainer email="robot@example.com">robot</maintainer>
  <license>Apache-2.0</license>

  <depend>rclpy</depend>
  <depend>std_msgs</depend>

  <test_depend>ament_copyright</test_depend>
  <test_depend>ament_flake8</test_depend>
  <test_depend>ament_pep257</test_depend>
  <test_depend>python3-pytest</test_depend>

  <export>
    <build_type>ament_python</build_type>
  </export>
</package>
XML

  cat > "$pkg_dir/setup.cfg" <<'CFG'
[develop]
script_dir=$base/lib/lekiwi_ros_bridge
[install]
install_scripts=$base/lib/lekiwi_ros_bridge
CFG

  cat > "$pkg_dir/setup.py" <<'PY'
from glob import glob

from setuptools import find_packages, setup

package_name = "lekiwi_ros_bridge"

setup(
    name=package_name,
    version="0.0.1",
    packages=find_packages(exclude=["test"]),
    data_files=[
        ("share/ament_index/resource_index/packages", [f"resource/{package_name}"]),
        (f"share/{package_name}", ["package.xml"]),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="robot",
    maintainer_email="robot@example.com",
    description="Milestone 1 ROS2 bridge for LeKiwi",
    license="Apache-2.0",
    tests_require=["pytest"],
    entry_points={
        "console_scripts": [
            "lekiwi_host_node = lekiwi_ros_bridge.lekiwi_host_node:main",
            "action_publisher = lekiwi_ros_bridge.action_publisher_node:main",
            "observation_echo = lekiwi_ros_bridge.observation_echo_node:main",
        ],
    },
)
PY

  cat > "$pkg_dir/lekiwi_ros_bridge/lekiwi_host_node.py" <<'PY'
import base64
import json
import time
from typing import Any

import rclpy
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from std_msgs.msg import String


STATE_KEYS = (
    "arm_shoulder_pan.pos",
    "arm_shoulder_lift.pos",
    "arm_elbow_flex.pos",
    "arm_wrist_flex.pos",
    "arm_wrist_roll.pos",
    "arm_gripper.pos",
    "x.vel",
    "y.vel",
    "theta.vel",
)


class MockLeKiwi:
    def __init__(self) -> None:
        self.last_action = {key: 0.0 for key in STATE_KEYS}
        self.cameras = {}

    def connect(self) -> None:
        pass

    def send_action(self, action: dict[str, float]) -> dict[str, float]:
        self.last_action.update(action)
        return self.last_action

    def get_observation(self) -> dict[str, float]:
        return dict(self.last_action)

    def stop_base(self) -> None:
        self.last_action["x.vel"] = 0.0
        self.last_action["y.vel"] = 0.0
        self.last_action["theta.vel"] = 0.0

    def disconnect(self) -> None:
        pass


class LeKiwiRosHost(Node):
    def __init__(self) -> None:
        super().__init__("lekiwi_ros_host")

        self.declare_parameter("mock", True)
        self.declare_parameter("robot_id", "my_awesome_kiwi")
        self.declare_parameter("port", "/dev/ttyACM0")
        self.declare_parameter("disable_cameras", True)
        self.declare_parameter("max_loop_freq_hz", 30.0)
        self.declare_parameter("watchdog_timeout_ms", 500.0)

        self.mock = bool(self.get_parameter("mock").value)
        self.max_loop_freq_hz = float(self.get_parameter("max_loop_freq_hz").value)
        self.watchdog_timeout_s = float(self.get_parameter("watchdog_timeout_ms").value) / 1000.0

        self.qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
            reliability=ReliabilityPolicy.BEST_EFFORT,
            durability=DurabilityPolicy.VOLATILE,
        )

        self.robot = self._make_robot()
        self.robot.connect()

        self.last_cmd_time = time.monotonic()
        self.watchdog_active = False

        self.action_sub = self.create_subscription(
            String,
            "/lekiwi/action",
            self.on_action,
            self.qos,
        )
        self.obs_pub = self.create_publisher(String, "/lekiwi/observation", self.qos)
        self.timer = self.create_timer(1.0 / self.max_loop_freq_hz, self.on_timer)

        mode = "mock" if self.mock else "real robot"
        self.get_logger().info(f"LeKiwi ROS host started in {mode} mode")

    def _make_robot(self) -> Any:
        if self.mock:
            return MockLeKiwi()

        from lerobot.robots.lekiwi import LeKiwi
        from lerobot.robots.lekiwi.config_lekiwi import LeKiwiConfig

        kwargs: dict[str, Any] = {
            "id": str(self.get_parameter("robot_id").value),
            "port": str(self.get_parameter("port").value),
        }
        if bool(self.get_parameter("disable_cameras").value):
            kwargs["cameras"] = {}

        return LeKiwi(LeKiwiConfig(**kwargs))

    def on_action(self, msg: String) -> None:
        try:
            action = json.loads(msg.data)
            if not isinstance(action, dict):
                raise ValueError("action JSON must be an object")
        except Exception as exc:
            self.get_logger().warning(f"Bad action message: {exc}")
            return

        action.setdefault("x.vel", 0.0)
        action.setdefault("y.vel", 0.0)
        action.setdefault("theta.vel", 0.0)

        try:
            self.robot.send_action(action)
        except Exception as exc:
            self.get_logger().error(f"robot.send_action failed: {exc}")
            return

        self.last_cmd_time = time.monotonic()
        self.watchdog_active = False

    def on_timer(self) -> None:
        now = time.monotonic()
        if now - self.last_cmd_time > self.watchdog_timeout_s and not self.watchdog_active:
            self.get_logger().warning("No recent command; stopping base")
            self.watchdog_active = True
            try:
                self.robot.stop_base()
            except Exception as exc:
                self.get_logger().error(f"robot.stop_base failed: {exc}")

        try:
            observation = self.robot.get_observation()
            encoded = self._json_safe_observation(observation)
            self.obs_pub.publish(String(data=json.dumps(encoded)))
        except Exception as exc:
            self.get_logger().error(f"publishing observation failed: {exc}")

    def _json_safe_observation(self, observation: dict[str, Any]) -> dict[str, Any]:
        encoded: dict[str, Any] = {}
        for key, value in observation.items():
            if hasattr(value, "shape"):
                encoded[key] = self._encode_array(key, value)
            elif hasattr(value, "item"):
                encoded[key] = value.item()
            else:
                encoded[key] = value
        return encoded

    def _encode_array(self, key: str, value: Any) -> Any:
        if len(value.shape) == 3:
            import cv2

            ok, buffer = cv2.imencode(".jpg", value, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
            if not ok:
                self.get_logger().warning(f"failed to encode image {key}")
                return ""
            return base64.b64encode(buffer).decode("utf-8")

        return value.tolist()

    def destroy_node(self) -> None:
        try:
            self.robot.disconnect()
        finally:
            super().destroy_node()


def main() -> None:
    rclpy.init()
    node = LeKiwiRosHost()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
PY

  cat > "$pkg_dir/lekiwi_ros_bridge/action_publisher_node.py" <<'PY'
import json

import rclpy
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from std_msgs.msg import String


class ActionPublisher(Node):
    def __init__(self) -> None:
        super().__init__("lekiwi_action_publisher")

        self.declare_parameter("rate_hz", 5.0)
        self.declare_parameter("x_vel", 0.0)
        self.declare_parameter("y_vel", 0.0)
        self.declare_parameter("theta_vel", 0.0)

        qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
            reliability=ReliabilityPolicy.BEST_EFFORT,
            durability=DurabilityPolicy.VOLATILE,
        )
        self.pub = self.create_publisher(String, "/lekiwi/action", qos)

        rate_hz = float(self.get_parameter("rate_hz").value)
        self.timer = self.create_timer(1.0 / rate_hz, self.on_timer)

    def on_timer(self) -> None:
        action = {
            "x.vel": float(self.get_parameter("x_vel").value),
            "y.vel": float(self.get_parameter("y_vel").value),
            "theta.vel": float(self.get_parameter("theta_vel").value),
        }
        self.pub.publish(String(data=json.dumps(action)))


def main() -> None:
    rclpy.init()
    node = ActionPublisher()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
PY

  cat > "$pkg_dir/lekiwi_ros_bridge/observation_echo_node.py" <<'PY'
import json
import time

import rclpy
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from std_msgs.msg import String


class ObservationEcho(Node):
    def __init__(self) -> None:
        super().__init__("lekiwi_observation_echo")
        qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
            reliability=ReliabilityPolicy.BEST_EFFORT,
            durability=DurabilityPolicy.VOLATILE,
        )
        self.last_print = 0.0
        self.sub = self.create_subscription(String, "/lekiwi/observation", self.on_observation, qos)

    def on_observation(self, msg: String) -> None:
        now = time.monotonic()
        if now - self.last_print < 1.0:
            return
        self.last_print = now

        obs = json.loads(msg.data)
        summary = {
            "x.vel": obs.get("x.vel"),
            "y.vel": obs.get("y.vel"),
            "theta.vel": obs.get("theta.vel"),
            "keys": sorted(obs.keys()),
        }
        self.get_logger().info(json.dumps(summary))


def main() -> None:
    rclpy.init()
    node = ObservationEcho()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
PY
}

build_bridge_package() {
  log "Building lekiwi_ros_bridge"
  # shellcheck disable=SC1091
  source "/opt/ros/$ROS_DISTRO_NAME/setup.bash"
  # shellcheck disable=SC1091
  source "$VENV_DIR/bin/activate"

  cd "$ROS_WS"
  rm -rf build/lekiwi_ros_bridge install/lekiwi_ros_bridge
  colcon build --symlink-install --packages-select lekiwi_ros_bridge
  # shellcheck disable=SC1091
  source "$ROS_WS/install/setup.bash"
  python -c "import lekiwi_ros_bridge; print(lekiwi_ros_bridge.__file__)"
}

print_next_steps() {
  cat <<EOF

Setup complete.

Open a new terminal on this machine and run:

  source /opt/ros/$ROS_DISTRO_NAME/setup.bash
  source "$VENV_DIR/bin/activate"
  cd "$ROS_WS"
  source install/setup.bash
  ros2 run lekiwi_ros_bridge lekiwi_host_node --ros-args -p mock:=true

In another terminal on the same ROS2 network:

  source /opt/ros/$ROS_DISTRO_NAME/setup.bash
  source "$VENV_DIR/bin/activate"
  cd "$ROS_WS"
  source install/setup.bash
  ros2 run lekiwi_ros_bridge observation_echo

In a third terminal:

  source /opt/ros/$ROS_DISTRO_NAME/setup.bash
  source "$VENV_DIR/bin/activate"
  cd "$ROS_WS"
  source install/setup.bash
  ros2 run lekiwi_ros_bridge action_publisher --ros-args -p x_vel:=0.1

For multi-machine discovery, set the same domain ID on every machine:

  export ROS_DOMAIN_ID=23

EOF
}

main() {
  require_ubuntu_2404_arm64
  install_ros2_jazzy
  clone_or_update_lerobot
  create_lerobot_venv
  write_bridge_package
  build_bridge_package
  print_next_steps
}

main "$@"
