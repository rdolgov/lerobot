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