#!/usr/bin/env python

from __future__ import annotations

import argparse
import math
import select
import sys
import termios
import time
import tty
from collections.abc import Iterable
from contextlib import contextmanager
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SRC_ROOT = REPO_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))


WHEEL_NAMES = ("base_left_wheel", "base_back_wheel", "base_right_wheel")
SETUP_ORDER = ("base_right_wheel", "base_back_wheel", "base_left_wheel")

WHEEL_IDS = {
    "base_left_wheel": 7,
    "base_back_wheel": 8,
    "base_right_wheel": 9,
}

MOTION_NAMES = ("forward", "backward", "left", "right", "rotate_left", "rotate_right")
KEY_MOTIONS = {
    "w": "forward",
    "s": "backward",
    "a": "left",
    "d": "right",
    "z": "rotate_left",
    "x": "rotate_right",
}


def make_wheels() -> dict:
    try:
        from lerobot.motors import Motor, MotorNormMode
    except ModuleNotFoundError as exc:
        raise SystemExit(
            f"Missing Python dependency '{exc.name}'. Run this from the project environment, for example:\n"
            "  uv run python my-scripts/kiwi-scripts/kiwi-wheel-only.py <command> ...\n"
            "or activate the environment that has LeRobot dependencies installed and run it with `python`."
        ) from exc

    return {
        name: Motor(id_, "sts3215", MotorNormMode.RANGE_M100_100) for name, id_ in WHEEL_IDS.items()
    }


def make_bus(port: str):
    try:
        from lerobot.motors.feetech import FeetechMotorsBus
    except ModuleNotFoundError as exc:
        raise SystemExit(
            f"Missing Python dependency '{exc.name}'. Run this from the project environment, for example:\n"
            "  uv run python my-scripts/kiwi-scripts/kiwi-wheel-only.py <command> ...\n"
            "or activate the environment that has LeRobot dependencies installed and run it with `python`."
        ) from exc

    return FeetechMotorsBus(port=port, motors=make_wheels())


def degps_to_raw(degps: float) -> int:
    raw = int(round(degps * 4096.0 / 360.0))
    return max(-0x8000, min(0x7FFF, raw))


def body_to_wheel_raw(
    x: float,
    y: float,
    theta: float,
    *,
    wheel_radius: float,
    base_radius: float,
    max_raw: int,
) -> dict[str, int]:
    theta_rad = theta * math.pi / 180.0
    body_velocity = (x, y, theta_rad)
    angles = tuple(math.radians(angle - 90) for angle in (240, 0, 120))

    wheel_degps: list[float] = []
    for angle in angles:
        linear_speed = (
            math.cos(angle) * body_velocity[0]
            + math.sin(angle) * body_velocity[1]
            + base_radius * body_velocity[2]
        )
        wheel_degps.append((linear_speed / wheel_radius) * 180.0 / math.pi)

    max_computed_raw = max(abs(degps) * 4096.0 / 360.0 for degps in wheel_degps)
    if max_computed_raw > max_raw:
        scale = max_raw / max_computed_raw
        wheel_degps = [degps * scale for degps in wheel_degps]

    return dict(zip(WHEEL_NAMES, (degps_to_raw(degps) for degps in wheel_degps), strict=True))


def stop_wheels(bus) -> None:
    bus.sync_write("Goal_Velocity", dict.fromkeys(WHEEL_NAMES, 0), normalize=False, num_retry=5)


def close_bus(bus, *, stop: bool, disable_torque: bool) -> None:
    if not bus.is_connected:
        return

    if stop:
        try:
            stop_wheels(bus)
        except Exception as exc:
            print(f"Could not send stop command before disconnect: {exc}")

    try:
        bus.disconnect(disable_torque=disable_torque)
    except Exception as exc:
        print(f"Disconnect with disable_torque={disable_torque} failed: {exc}")
        if bus.is_connected:
            bus.disconnect(disable_torque=False)


def configure_wheels(bus) -> None:
    try:
        from lerobot.motors.feetech import OperatingMode
    except ModuleNotFoundError as exc:
        raise SystemExit(
            f"Missing Python dependency '{exc.name}'. Run this from the project environment, for example:\n"
            "  uv run python my-scripts/kiwi-scripts/kiwi-wheel-only.py <command> ...\n"
            "or activate the environment that has LeRobot dependencies installed and run it with `python`."
        ) from exc

    bus.disable_torque(list(WHEEL_NAMES), num_retry=5)
    bus.configure_motors()
    for name in WHEEL_NAMES:
        bus.write("Operating_Mode", name, OperatingMode.VELOCITY.value)
    bus.enable_torque(list(WHEEL_NAMES), num_retry=5)


def scan(args: argparse.Namespace) -> None:
    try:
        from lerobot.motors.feetech import FeetechMotorsBus
    except ModuleNotFoundError as exc:
        raise SystemExit(
            f"Missing Python dependency '{exc.name}'. Run this from the project environment, for example:\n"
            "  uv run python my-scripts/kiwi-scripts/kiwi-wheel-only.py <command> ...\n"
            "or activate the environment that has LeRobot dependencies installed and run it with `python`."
        ) from exc

    found = FeetechMotorsBus.scan_port(args.port)
    if not found:
        print("No motors found.")


def setup(args: argparse.Namespace) -> None:
    bus = make_bus(args.port)
    try:
        print("Wheel-only LeKiwi setup")
        print("Connect exactly one wheel motor at a time. Leave the arm disconnected.")
        for name in SETUP_ORDER:
            motor_id = WHEEL_IDS[name]
            print(f"\nTarget: {name} -> id {motor_id}")
            input("Connect ONLY this motor to the controller board, then press ENTER.")
            bus.setup_motor(name, initial_baudrate=args.initial_baudrate, initial_id=args.initial_id)
            print(f"Set {name} to id {motor_id}")
        print("\nDone. Reconnect all three wheel motors before running the test command.")
    finally:
        close_bus(bus, stop=False, disable_torque=False)


def motion_to_body(name: str, speed: float, turn_speed: float) -> tuple[float, float, float]:
    if name == "forward":
        return speed, 0.0, 0.0
    if name == "backward":
        return -speed, 0.0, 0.0
    if name == "left":
        return 0.0, speed, 0.0
    if name == "right":
        return 0.0, -speed, 0.0
    if name == "rotate_left":
        return 0.0, 0.0, turn_speed
    if name == "rotate_right":
        return 0.0, 0.0, -turn_speed
    raise ValueError(name)


def run_motions(args: argparse.Namespace, motions: Iterable[str]) -> None:
    bus = make_bus(args.port)
    try:
        bus.connect()
        configure_wheels(bus)

        print("Wheel IDs found. Starting low-speed test.")
        for name in motions:
            x, y, theta = motion_to_body(name, args.speed, args.turn_speed)
            wheel_raw = body_to_wheel_raw(
                x,
                y,
                theta,
                wheel_radius=args.wheel_radius,
                base_radius=args.base_radius,
                max_raw=args.max_raw,
            )
            print(f"\n{name}: body=({x:.3f}, {y:.3f}, {theta:.1f}) wheel_raw={wheel_raw}")
            bus.sync_write("Goal_Velocity", wheel_raw, normalize=False)
            time.sleep(args.duration)
            present = bus.sync_read("Present_Velocity", list(WHEEL_NAMES), normalize=False, num_retry=2)
            print(f"present_velocity={present}")
            stop_wheels(bus)
            time.sleep(args.pause)

        print("\nDone. Wheels stopped.")
    finally:
        close_bus(bus, stop=True, disable_torque=True)


def test(args: argparse.Namespace) -> None:
    run_motions(args, args.motions)


@contextmanager
def raw_terminal():
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
        yield
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


def print_keyboard_status(speed: float, turn_speed: float, deadman_timeout: float) -> None:
    print("Keyboard control active. Lift the base first for initial testing.")
    print("w/s/a/d: move | z/x: rotate | r/f: speed up/down | space: stop | q: quit")
    if deadman_timeout > 0:
        print(f"Deadman timeout: {deadman_timeout:.1f}s. Hold a key to keep moving.")
    else:
        print("Deadman timeout disabled. Press space to stop.")
    print(f"Speed: {speed:.3f} m/s, turn: {turn_speed:.1f} deg/s")


def keyboard(args: argparse.Namespace) -> None:
    bus = make_bus(args.port)
    current_motion: str | None = None
    last_motion_key_time = 0.0
    last_sent: dict[str, int] | None = None
    speed_scale = 1.0

    try:
        bus.connect()
        configure_wheels(bus)
        print_keyboard_status(args.speed, args.turn_speed, args.deadman_timeout)

        with raw_terminal():
            while True:
                now = time.monotonic()
                readable, _, _ = select.select([sys.stdin], [], [], 1.0 / args.command_hz)
                if readable:
                    key = sys.stdin.read(1).lower()
                    now = time.monotonic()

                    if key == "\x03":
                        raise KeyboardInterrupt
                    if key == "q":
                        print("\nQuit requested.")
                        break
                    if key == " ":
                        current_motion = None
                        last_motion_key_time = 0.0
                        stop_wheels(bus)
                        last_sent = dict.fromkeys(WHEEL_NAMES, 0)
                        print("\nStopped.")
                        continue
                    if key == "r":
                        speed_scale = min(speed_scale * 1.25, args.max_speed_scale)
                        print(
                            f"\nSpeed: {args.speed * speed_scale:.3f} m/s, "
                            f"turn: {args.turn_speed * speed_scale:.1f} deg/s"
                        )
                        continue
                    if key == "f":
                        speed_scale = max(speed_scale / 1.25, args.min_speed_scale)
                        print(
                            f"\nSpeed: {args.speed * speed_scale:.3f} m/s, "
                            f"turn: {args.turn_speed * speed_scale:.1f} deg/s"
                        )
                        continue
                    if key in KEY_MOTIONS:
                        current_motion = KEY_MOTIONS[key]
                        last_motion_key_time = now

                motion_timed_out = (
                    args.deadman_timeout > 0
                    and current_motion is not None
                    and now - last_motion_key_time > args.deadman_timeout
                )
                if current_motion is None or motion_timed_out:
                    wheel_raw = dict.fromkeys(WHEEL_NAMES, 0)
                else:
                    x, y, theta = motion_to_body(
                        current_motion,
                        args.speed * speed_scale,
                        args.turn_speed * speed_scale,
                    )
                    wheel_raw = body_to_wheel_raw(
                        x,
                        y,
                        theta,
                        wheel_radius=args.wheel_radius,
                        base_radius=args.base_radius,
                        max_raw=args.max_raw,
                    )

                if wheel_raw != last_sent:
                    bus.sync_write("Goal_Velocity", wheel_raw, normalize=False)
                    last_sent = wheel_raw
    except KeyboardInterrupt:
        print("\nKeyboard interrupt received.")
    finally:
        close_bus(bus, stop=True, disable_torque=True)


def jog(args: argparse.Namespace) -> None:
    bus = make_bus(args.port)
    try:
        bus.connect()
        configure_wheels(bus)
        values = dict.fromkeys(WHEEL_NAMES, 0)
        values[args.wheel] = args.raw
        print(f"Jogging {args.wheel} at raw velocity {args.raw} for {args.duration:.2f}s")
        bus.sync_write("Goal_Velocity", values, normalize=False)
        time.sleep(args.duration)
        print(bus.sync_read("Present_Velocity", list(WHEEL_NAMES), normalize=False, num_retry=2))
    finally:
        close_bus(bus, stop=True, disable_torque=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Wheel-only setup and smoke test for a LeKiwi base.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    scan_parser = subparsers.add_parser("scan", help="Scan a controller port for Feetech motor IDs.")
    scan_parser.add_argument("--port", required=True)
    scan_parser.set_defaults(func=scan)

    setup_parser = subparsers.add_parser("setup", help="Assign LeKiwi wheel IDs 9, 8, then 7.")
    setup_parser.add_argument("--port", required=True)
    setup_parser.add_argument("--initial-baudrate", type=int, default=None)
    setup_parser.add_argument("--initial-id", type=int, default=None)
    setup_parser.set_defaults(func=setup)

    test_parser = subparsers.add_parser("test", help="Run a low-speed body-motion test.")
    test_parser.add_argument("--port", required=True)
    test_parser.add_argument("--motions", nargs="+", choices=MOTION_NAMES, default=list(MOTION_NAMES))
    test_parser.add_argument("--speed", type=float, default=0.08, help="Linear speed in m/s.")
    test_parser.add_argument("--turn-speed", type=float, default=20.0, help="Angular speed in deg/s.")
    test_parser.add_argument("--duration", type=float, default=0.7)
    test_parser.add_argument("--pause", type=float, default=0.4)
    test_parser.add_argument("--wheel-radius", type=float, default=0.05)
    test_parser.add_argument("--base-radius", type=float, default=0.125)
    test_parser.add_argument("--max-raw", type=int, default=800)
    test_parser.set_defaults(func=test)

    keyboard_parser = subparsers.add_parser("keyboard", help="Control the wheel base from the keyboard.")
    keyboard_parser.add_argument("--port", required=True)
    keyboard_parser.add_argument("--speed", type=float, default=0.08, help="Base linear speed in m/s.")
    keyboard_parser.add_argument("--turn-speed", type=float, default=20.0, help="Base angular speed in deg/s.")
    keyboard_parser.add_argument("--deadman-timeout", type=float, default=0.8)
    keyboard_parser.add_argument("--command-hz", type=float, default=20.0)
    keyboard_parser.add_argument("--wheel-radius", type=float, default=0.05)
    keyboard_parser.add_argument("--base-radius", type=float, default=0.125)
    keyboard_parser.add_argument("--max-raw", type=int, default=800)
    keyboard_parser.add_argument("--min-speed-scale", type=float, default=0.5)
    keyboard_parser.add_argument("--max-speed-scale", type=float, default=3.0)
    keyboard_parser.set_defaults(func=keyboard)

    jog_parser = subparsers.add_parser("jog", help="Jog one wheel for wiring/direction debugging.")
    jog_parser.add_argument("--port", required=True)
    jog_parser.add_argument("--wheel", choices=WHEEL_NAMES, required=True)
    jog_parser.add_argument("--raw", type=int, default=300)
    jog_parser.add_argument("--duration", type=float, default=0.5)
    jog_parser.set_defaults(func=jog)

    return parser


def main() -> None:
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
