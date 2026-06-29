#!/usr/bin/env python3

"""Publish LeKiwi camera frames as ROS2 compressed image topics.

Run this on the Pi that owns the mobile base cameras:

    source ~/ros2_lekiwi_env.sh
    cd ~/dev/fork/rdolgov/lerobot
    python examples/lekiwi/ios_control/ros2_camera_publisher.py

It publishes:

    /lekiwi/front/image/compressed
    /lekiwi/wrist/image/compressed
"""

from __future__ import annotations

import argparse
import logging
import time
from dataclasses import dataclass

import cv2
import rclpy
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import CompressedImage

LOGGER = logging.getLogger("lekiwi_camera_publisher")


@dataclass
class CameraSpec:
    name: str
    path: str
    topic: str
    width: int
    height: int
    fps: int
    rotation: int


class CameraHandle:
    def __init__(self, spec: CameraSpec, jpeg_quality: int, backend: int, fourcc: str) -> None:
        self.spec = spec
        self.jpeg_quality = jpeg_quality
        self.capture = cv2.VideoCapture(spec.path, backend)
        self.capture.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*fourcc))
        self.capture.set(cv2.CAP_PROP_FRAME_WIDTH, spec.width)
        self.capture.set(cv2.CAP_PROP_FRAME_HEIGHT, spec.height)
        self.capture.set(cv2.CAP_PROP_FPS, spec.fps)

        if not self.capture.isOpened():
            raise RuntimeError(f"Failed to open {spec.name} camera at {spec.path}")

    def read_compressed(self) -> bytes | None:
        ok, frame = self.capture.read()
        if not ok or frame is None:
            return None

        frame = rotate_frame(frame, self.spec.rotation)
        ok, encoded = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), self.jpeg_quality])
        if not ok:
            return None
        return encoded.tobytes()

    def release(self) -> None:
        self.capture.release()


class LeKiwiCameraPublisher(Node):
    def __init__(self, args: argparse.Namespace) -> None:
        super().__init__("lekiwi_camera_publisher")

        qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
            reliability=ReliabilityPolicy.BEST_EFFORT,
            durability=DurabilityPolicy.VOLATILE,
        )

        self._image_publishers: dict[str, object] = {}
        self.cameras: list[CameraHandle] = []
        self.timer = self.create_timer(1.0 / args.publish_fps, self.on_timer)

        specs = camera_specs_from_args(args)
        for spec in specs:
            handle = CameraHandle(
                spec=spec,
                jpeg_quality=args.jpeg_quality,
                backend=args.backend,
                fourcc=args.fourcc,
            )
            self.cameras.append(handle)
            self._image_publishers[spec.name] = self.create_publisher(CompressedImage, spec.topic, qos)
            self.get_logger().info(f"Publishing {spec.name} camera {spec.path} on {spec.topic}")

        self.frame_count = 0
        self.last_log_time = time.monotonic()

    def on_timer(self) -> None:
        for camera in self.cameras:
            data = camera.read_compressed()
            if data is None:
                self.get_logger().warning(f"No frame from {camera.spec.name}")
                continue

            msg = CompressedImage()
            msg.header.stamp = self.get_clock().now().to_msg()
            msg.header.frame_id = f"lekiwi_{camera.spec.name}_camera"
            msg.format = "jpeg"
            msg.data = data
            self._image_publishers[camera.spec.name].publish(msg)

        self.frame_count += 1
        now = time.monotonic()
        if now - self.last_log_time > 5:
            self.get_logger().info(f"Published camera frames at {self.frame_count / (now - self.last_log_time):.1f} Hz")
            self.frame_count = 0
            self.last_log_time = now

    def destroy_node(self) -> None:
        for camera in self.cameras:
            camera.release()
        super().destroy_node()


def rotate_frame(frame, rotation: int):
    normalized = rotation % 360
    if normalized == 90:
        return cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    if normalized == 180:
        return cv2.rotate(frame, cv2.ROTATE_180)
    if normalized == 270:
        return cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
    return frame


def camera_specs_from_args(args: argparse.Namespace) -> list[CameraSpec]:
    specs: list[CameraSpec] = []
    if not args.disable_front:
        specs.append(
            CameraSpec(
                name="front",
                path=args.front_path,
                topic=args.front_topic,
                width=args.front_width,
                height=args.front_height,
                fps=args.camera_fps,
                rotation=args.front_rotation,
            )
        )
    if not args.disable_wrist:
        specs.append(
            CameraSpec(
                name="wrist",
                path=args.wrist_path,
                topic=args.wrist_topic,
                width=args.wrist_width,
                height=args.wrist_height,
                fps=args.camera_fps,
                rotation=args.wrist_rotation,
            )
        )
    if not specs:
        raise ValueError("At least one camera must be enabled")
    return specs


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--front-path", default="/dev/video0")
    parser.add_argument("--wrist-path", default="/dev/video2")
    parser.add_argument("--front-topic", default="/lekiwi/front/image/compressed")
    parser.add_argument("--wrist-topic", default="/lekiwi/wrist/image/compressed")
    parser.add_argument("--front-width", type=int, default=640)
    parser.add_argument("--front-height", type=int, default=480)
    parser.add_argument("--wrist-width", type=int, default=480)
    parser.add_argument("--wrist-height", type=int, default=640)
    parser.add_argument("--front-rotation", type=int, choices=(0, 90, 180, 270), default=0)
    parser.add_argument("--wrist-rotation", type=int, choices=(0, 90, 180, 270), default=90)
    parser.add_argument("--camera-fps", type=int, default=30)
    parser.add_argument("--publish-fps", type=float, default=10.0)
    parser.add_argument("--jpeg-quality", type=int, default=80)
    parser.add_argument("--fourcc", default="MJPG")
    parser.add_argument("--backend", type=int, default=200, help="OpenCV backend. 200 is CAP_V4L2.")
    parser.add_argument("--disable-front", action="store_true")
    parser.add_argument("--disable-wrist", action="store_true")
    return parser.parse_args()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    args = parse_args()

    rclpy.init()
    node = LeKiwiCameraPublisher(args)
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
