#!/usr/bin/env python3

"""Control the LeKiwi arm from phone-friendly ROS2 JSON commands.

This node sits between the WebSocket bridge and the existing LeKiwi ROS host:

    iPhone app
      -> WebSocket bridge
      -> /lekiwi/arm/command
      -> this node
      -> /lekiwi/action
      -> lekiwi_host_node

The LeKiwi host remains the only process that talks to motors. This node only
translates desired arm joint targets into LeRobot-style action dictionaries.
"""

from __future__ import annotations

import argparse
import json
import logging
import math
import threading
import time
from typing import Any

import rclpy
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from std_msgs.msg import String

LOGGER = logging.getLogger("lekiwi_arm_controller")

BASE_STOP_ACTION = {
    "x.vel": 0.0,
    "y.vel": 0.0,
    "theta.vel": 0.0,
}

JOINT_LIMITS = {
    "arm_shoulder_pan.pos": (-180.0, 180.0),
    "arm_shoulder_lift.pos": (-180.0, 180.0),
    "arm_elbow_flex.pos": (-180.0, 180.0),
    "arm_wrist_flex.pos": (-180.0, 180.0),
    "arm_wrist_roll.pos": (-180.0, 180.0),
    "arm_gripper.pos": (0.0, 100.0),
}

JOINT_ALIASES = {
    "shoulder_pan": "arm_shoulder_pan.pos",
    "shoulderPan": "arm_shoulder_pan.pos",
    "shoulder_lift": "arm_shoulder_lift.pos",
    "shoulderLift": "arm_shoulder_lift.pos",
    "elbow_flex": "arm_elbow_flex.pos",
    "elbowFlex": "arm_elbow_flex.pos",
    "wrist_flex": "arm_wrist_flex.pos",
    "wristFlex": "arm_wrist_flex.pos",
    "wrist_roll": "arm_wrist_roll.pos",
    "wristRoll": "arm_wrist_roll.pos",
    "gripper": "arm_gripper.pos",
}


class LeKiwiArmController(Node):
    def __init__(self, args: argparse.Namespace) -> None:
        super().__init__("lekiwi_arm_controller")

        qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
            reliability=ReliabilityPolicy.BEST_EFFORT,
            durability=DurabilityPolicy.VOLATILE,
        )

        self.action_pub = self.create_publisher(String, args.action_topic, qos)
        self.command_sub = self.create_subscription(
            String,
            args.arm_command_topic,
            self._on_arm_command,
            qos,
        )
        self.observation_sub = self.create_subscription(
            String,
            args.observation_topic,
            self._on_observation,
            qos,
        )
        self.timer = self.create_timer(1.0 / args.publish_hz, self._on_timer)

        self.max_step = max(0.0, args.max_step)
        self.tolerance = max(0.0, args.tolerance)
        self.allow_without_observation = args.allow_without_observation

        self.latest_observation: dict[str, float] = {}
        self.target_joints: dict[str, float] = {}
        self.last_sent: dict[str, float] = {}
        self.last_missing_observation_log = 0.0
        self._lock = threading.Lock()

        self.get_logger().info(
            "Arm controller listening on "
            f"{args.arm_command_topic}; publishing merged actions to {args.action_topic}"
        )

    def _on_observation(self, msg: String) -> None:
        try:
            observation = json.loads(msg.data)
            if not isinstance(observation, dict):
                raise ValueError("observation JSON must be an object")
        except Exception as exc:
            self.get_logger().warning(f"Dropping malformed observation JSON: {exc}")
            return

        joint_state: dict[str, float] = {}
        for key in JOINT_LIMITS:
            value = maybe_float(observation.get(key))
            if value is not None:
                joint_state[key] = value

        if joint_state:
            with self._lock:
                self.latest_observation.update(joint_state)

    def _on_arm_command(self, msg: String) -> None:
        try:
            payload = json.loads(msg.data)
            if not isinstance(payload, dict):
                raise ValueError("arm command JSON must be an object")
        except Exception as exc:
            self.get_logger().warning(f"Dropping malformed arm command JSON: {exc}")
            return

        message_type = payload.get("type", "arm_command")
        if message_type == "arm_stop":
            with self._lock:
                self.target_joints = {}
            self.get_logger().info("Cleared arm target")
            return

        if message_type != "arm_command":
            self.get_logger().warning(f"Unsupported arm command type: {message_type!r}")
            return

        raw_joints = payload.get("joints", payload)
        if not isinstance(raw_joints, dict):
            self.get_logger().warning("Arm command must contain a 'joints' object")
            return

        targets: dict[str, float] = {}
        for raw_key, raw_value in raw_joints.items():
            key = canonical_joint_key(str(raw_key))
            value = maybe_float(raw_value)
            if key is None or value is None:
                continue
            low, high = JOINT_LIMITS[key]
            targets[key] = clamp(value, low, high)

        if not targets:
            self.get_logger().warning("Arm command did not contain recognized joint targets")
            return

        with self._lock:
            self.target_joints = targets

        self.get_logger().info(
            "New arm target: "
            + ", ".join(f"{key}={value:.1f}" for key, value in sorted(targets.items()))
        )

    def _on_timer(self) -> None:
        with self._lock:
            targets = dict(self.target_joints)
            observation = dict(self.latest_observation)
            last_sent = dict(self.last_sent)

        if not targets:
            return

        if not observation and not self.allow_without_observation:
            now = time.monotonic()
            if now - self.last_missing_observation_log > 2.0:
                self.get_logger().warning(
                    "Waiting for /lekiwi/observation before moving the arm. "
                    "Start lekiwi_host_node first, or pass --allow-without-observation."
                )
                self.last_missing_observation_log = now
            return

        action = dict(BASE_STOP_ACTION)
        active = False

        for key, target in targets.items():
            present = observation.get(key, last_sent.get(key))
            if present is None or self.max_step <= 0:
                next_value = target
            else:
                delta = target - present
                if abs(delta) <= self.tolerance:
                    next_value = target
                else:
                    active = True
                    next_value = present + math.copysign(min(abs(delta), self.max_step), delta)

            low, high = JOINT_LIMITS[key]
            next_value = clamp(next_value, low, high)
            if abs(target - next_value) > self.tolerance:
                active = True
            action[key] = next_value

        self.action_pub.publish(String(data=json.dumps(action)))

        with self._lock:
            self.last_sent.update({key: action[key] for key in targets})
            if not active:
                self.target_joints = {}


def canonical_joint_key(key: str) -> str | None:
    if key in JOINT_LIMITS:
        return key
    if key in JOINT_ALIASES:
        return JOINT_ALIASES[key]
    if key.startswith("arm_") and not key.endswith(".pos"):
        candidate = f"{key}.pos"
        if candidate in JOINT_LIMITS:
            return candidate
    return None


def maybe_float(value: Any) -> float | None:
    try:
        if value is None:
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def clamp(value: float, low: float, high: float) -> float:
    return min(max(value, low), high)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arm-command-topic", default="/lekiwi/arm/command")
    parser.add_argument("--observation-topic", default="/lekiwi/observation")
    parser.add_argument("--action-topic", default="/lekiwi/action")
    parser.add_argument(
        "--publish-hz",
        type=float,
        default=10.0,
        help="Maximum rate for publishing stepped arm actions",
    )
    parser.add_argument(
        "--max-step",
        type=float,
        default=4.0,
        help="Maximum joint target change per publish tick. Use 0 to disable stepping.",
    )
    parser.add_argument(
        "--tolerance",
        type=float,
        default=0.5,
        help="Target tolerance before the controller stops publishing",
    )
    parser.add_argument(
        "--allow-without-observation",
        action="store_true",
        help="Publish targets before receiving arm joint observations",
    )
    return parser.parse_args()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    args = parse_args()

    rclpy.init()
    node = LeKiwiArmController(args)
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
