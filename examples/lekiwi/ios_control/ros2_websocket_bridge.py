#!/usr/bin/env python3

"""WebSocket bridge for controlling LeKiwi from a phone.

The bridge talks ROS2 on one side and plain WebSocket JSON on the other:

    iPhone app <-> ws://<bridge-host>:8765 <->
      /lekiwi/action
      /lekiwi/arm/command
      /lekiwi/observation
      /lekiwi/front/image/compressed
      /lekiwi/wrist/image/compressed

Run it from a ROS2 terminal:

    source ~/ros2_lekiwi_env.sh
    python examples/lekiwi/ios_control/ros2_websocket_bridge.py
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import logging
import signal
import threading
import time
from dataclasses import dataclass
from typing import Any

try:
    import websockets
except ImportError as exc:  # pragma: no cover - user setup guard
    raise SystemExit(
        "Missing dependency 'websockets'. Install it in the ROS2 LeRobot venv with:\n"
        "  python -m pip install websockets"
    ) from exc

import rclpy
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import CompressedImage
from std_msgs.msg import String

LOGGER = logging.getLogger("lekiwi_ios_bridge")


@dataclass(frozen=True)
class Command:
    x: float = 0.0
    y: float = 0.0
    theta: float = 0.0

    def as_lerobot_action(self) -> dict[str, float]:
        return {
            "x.vel": self.x,
            "y.vel": self.y,
            "theta.vel": self.theta,
        }


class LeKiwiWebSocketBridge(Node):
    def __init__(self, args: argparse.Namespace) -> None:
        super().__init__("lekiwi_ios_websocket_bridge")

        qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
            reliability=ReliabilityPolicy.BEST_EFFORT,
            durability=DurabilityPolicy.VOLATILE,
        )

        self.action_pub = self.create_publisher(String, "/lekiwi/action", qos)
        self.arm_command_pub = self.create_publisher(String, args.arm_command_topic, qos)
        self.observation_sub = self.create_subscription(
            String,
            "/lekiwi/observation",
            self._on_observation,
            qos,
        )
        self.front_image_sub = self.create_subscription(
            CompressedImage,
            args.front_image_topic,
            lambda msg: self._on_image("front", msg),
            qos,
        )
        self.wrist_image_sub = self.create_subscription(
            CompressedImage,
            args.wrist_image_topic,
            lambda msg: self._on_image("wrist", msg),
            qos,
        )
        self.watchdog_timer = self.create_timer(0.1, self._on_watchdog)

        self.command_timeout_s = args.command_timeout_s
        self.last_command_time = 0.0
        self.latest_observation: dict[str, Any] | None = None
        self.latest_images: dict[str, str] = {}
        self.latest_observation_seq = 0
        self._lock = threading.Lock()

    def _on_observation(self, msg: String) -> None:
        try:
            observation = json.loads(msg.data)
        except json.JSONDecodeError:
            self.get_logger().warning("Dropping malformed observation JSON")
            return

        with self._lock:
            self.latest_observation = observation
            self.latest_observation_seq += 1

    def _on_image(self, name: str, msg: CompressedImage) -> None:
        with self._lock:
            self.latest_images[name] = base64.b64encode(bytes(msg.data)).decode("utf-8")
            self.latest_observation_seq += 1

    def _on_watchdog(self) -> None:
        if self.last_command_time <= 0:
            return
        if time.monotonic() - self.last_command_time > self.command_timeout_s:
            self.publish_command(Command())
            self.last_command_time = 0.0

    def publish_command(self, command: Command) -> None:
        self.action_pub.publish(String(data=json.dumps(command.as_lerobot_action())))

    def publish_arm_stop(self) -> None:
        self.arm_command_pub.publish(String(data=json.dumps({"type": "arm_stop"})))

    def publish_client_payload(self, payload: dict[str, Any]) -> None:
        message_type = payload.get("type", "command")
        if message_type in {"arm_command", "arm_stop"}:
            self.arm_command_pub.publish(String(data=json.dumps(payload)))
            return

        command = command_from_payload(payload)
        self.publish_command(command)
        self.last_command_time = time.monotonic()

    def snapshot_observation(self) -> tuple[int, dict[str, Any] | None]:
        with self._lock:
            if self.latest_observation is None and not self.latest_images:
                return self.latest_observation_seq, None
            observation = dict(self.latest_observation or {})
            observation.update(self.latest_images)
            return self.latest_observation_seq, observation


def command_from_payload(payload: dict[str, Any]) -> Command:
    message_type = payload.get("type", "command")
    if message_type == "stop":
        return Command()
    if message_type != "command":
        raise ValueError(f"unsupported message type {message_type!r}")

    return Command(
        x=float(payload.get("x", payload.get("x.vel", 0.0))),
        y=float(payload.get("y", payload.get("y.vel", 0.0))),
        theta=float(payload.get("theta", payload.get("theta.vel", 0.0))),
    )


async def handle_client(websocket: Any, node: LeKiwiWebSocketBridge) -> None:
    peer = getattr(websocket, "remote_address", None)
    LOGGER.info("client connected: %s", peer)

    receive_task = asyncio.create_task(receive_commands(websocket, node))
    send_task = asyncio.create_task(send_observations(websocket, node))

    done, pending = await asyncio.wait(
        {receive_task, send_task},
        return_when=asyncio.FIRST_COMPLETED,
    )
    for task in pending:
        task.cancel()
    for task in done:
        if task.cancelled():
            continue
        exc = task.exception()
        if exc is not None:
            LOGGER.info("client task ended: %s", exc)

    node.publish_command(Command())
    node.publish_arm_stop()
    LOGGER.info("client disconnected: %s", peer)


async def receive_commands(websocket: Any, node: LeKiwiWebSocketBridge) -> None:
    await websocket.send(json.dumps({"type": "hello", "message": "lekiwi bridge ready"}))

    async for raw in websocket:
        try:
            payload = json.loads(raw)
            if payload.get("type") == "ping":
                await websocket.send(json.dumps({"type": "pong"}))
                continue
            node.publish_client_payload(payload)
        except Exception as exc:
            await websocket.send(json.dumps({"type": "error", "message": str(exc)}))


async def send_observations(websocket: Any, node: LeKiwiWebSocketBridge) -> None:
    last_sent_seq = -1
    while True:
        seq, observation = node.snapshot_observation()
        if observation is not None and seq != last_sent_seq:
            await websocket.send(
                json.dumps(
                    {
                        "type": "observation",
                        "seq": seq,
                        "observation": observation,
                    }
                )
            )
            last_sent_seq = seq
        await asyncio.sleep(0.1)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0", help="WebSocket bind host")
    parser.add_argument("--port", type=int, default=8765, help="WebSocket bind port")
    parser.add_argument(
        "--command-timeout-s",
        type=float,
        default=0.5,
        help="Publish a stop command if the phone stops sending commands",
    )
    parser.add_argument("--front-image-topic", default="/lekiwi/front/image/compressed")
    parser.add_argument("--wrist-image-topic", default="/lekiwi/wrist/image/compressed")
    parser.add_argument("--arm-command-topic", default="/lekiwi/arm/command")
    return parser.parse_args()


async def run_server(args: argparse.Namespace, node: LeKiwiWebSocketBridge) -> None:
    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop_event.set)
        except NotImplementedError:
            pass

    async with websockets.serve(
        lambda websocket, *unused: handle_client(websocket, node),
        args.host,
        args.port,
        max_size=None,
        ping_interval=20,
        ping_timeout=20,
    ):
        LOGGER.info("WebSocket bridge listening on ws://%s:%s", args.host, args.port)
        await stop_event.wait()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    args = parse_args()

    rclpy.init()
    node = LeKiwiWebSocketBridge(args)
    spin_thread = threading.Thread(target=rclpy.spin, args=(node,), daemon=True)
    spin_thread.start()

    try:
        asyncio.run(run_server(args, node))
    finally:
        node.publish_command(Command())
        node.publish_arm_stop()
        node.destroy_node()
        rclpy.shutdown()
        spin_thread.join(timeout=2)


if __name__ == "__main__":
    main()
