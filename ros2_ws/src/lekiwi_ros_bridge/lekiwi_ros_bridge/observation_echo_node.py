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