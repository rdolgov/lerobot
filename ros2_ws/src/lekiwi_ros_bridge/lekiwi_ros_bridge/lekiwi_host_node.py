import base64
import json
import time
import traceback
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
            self._send_action(action)
        except Exception as exc:
            message = f"robot.send_action failed ({type(exc).__name__}): {exc!r}"
            self.get_logger().error(
                f"{message}\n{traceback.format_exc()}"
            )
            return

        self.last_cmd_time = time.monotonic()
        self.watchdog_active = False

    def _send_action(self, action: dict[str, Any]) -> None:
        arm_action = {key: value for key, value in action.items() if key.endswith(".pos")}
        if self.mock or arm_action:
            self.robot.send_action(action)
            return

        base_wheel_goal_vel = self.robot._body_to_wheel_raw(
            float(action["x.vel"]),
            float(action["y.vel"]),
            float(action["theta.vel"]),
        )
        self.robot.bus.sync_write("Goal_Velocity", base_wheel_goal_vel)

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
