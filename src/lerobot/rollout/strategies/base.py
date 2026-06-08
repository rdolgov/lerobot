# Copyright 2025 The HuggingFace Inc. team. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Base rollout strategy: autonomous policy execution with no data recording."""

from __future__ import annotations

import logging
import os
import time

from lerobot.utils.robot_utils import precise_sleep

from ..context import RolloutContext
from .core import RolloutStrategy, send_next_action

logger = logging.getLogger(__name__)


def _env_flag(name: str) -> bool:
    return os.environ.get(name, "").lower() in {"1", "true", "yes", "on"}


def _record_timing(timing: dict[str, float], name: str, start: float) -> None:
    timing[name] = time.perf_counter() - start


def _merge_robot_observation_timing(robot, timing: dict[str, float]) -> None:
    robot_timing = getattr(getattr(robot, "inner", robot), "last_observation_timing", {})
    if robot_timing:
        timing.update(robot_timing)


def _include_in_breakdown(name: str) -> bool:
    return (
        name != "loop.total"
        and not name.startswith("action.marker.")
        and ".capture." not in name
        and not name.endswith(".frame_age")
    )


def _format_timing_breakdown(timing: dict[str, float]) -> str:
    total = timing.get("loop.total", 0.0)
    if total <= 0:
        return "no timing data"

    parts = [f"loop.total={total * 1000:.1f}ms"]
    slowest = sorted(
        ((name, value) for name, value in timing.items() if _include_in_breakdown(name)),
        key=lambda item: item[1],
        reverse=True,
    )
    for name, value in slowest[:12]:
        parts.append(f"{name}={value * 1000:.1f}ms/{(value / total) * 100:.0f}%")
    return ", ".join(parts)


def _action_source_from_timing(timing: dict[str, float], fps: float) -> str:
    if not timing.get("action.marker.requested_new_action", 0.0):
        return "interpolator-cache"
    if not timing.get("action.marker.received_new_action", 0.0):
        return "model-miss"

    # Sync ACT calls select_action every frame, but select_action often only
    # pops from its internal action queue. A real chunk refill is much slower.
    target_interval = 1.0 / fps
    if (
        timing.get("action.engine_get_action", 0.0) > target_interval
        or timing.get("inference.policy_select_action", 0.0) > 0.010
    ):
        return "chunk-refill"
    return "policy-cache"


def _ms(timing: dict[str, float], name: str) -> str:
    return f"{timing.get(name, 0.0) * 1000:.1f}ms"


def _format_camera_timing(timing: dict[str, float]) -> str:
    camera_names = sorted(
        {
            name.split(".")[2]
            for name in timing
            if name.startswith("robot.camera.") and len(name.split(".")) >= 4
        }
    )
    parts: list[str] = []
    for camera_name in camera_names:
        prefix = f"robot.camera.{camera_name}"
        parts.extend(
            [
                f"cam_{camera_name}={_ms(timing, f'{prefix}.read_latest')}",
                f"cam_{camera_name}_hw={_ms(timing, f'{prefix}.capture.read_hardware')}",
                f"cam_{camera_name}_img={_ms(timing, f'{prefix}.capture.postprocess_image')}",
                f"cam_{camera_name}_age={_ms(timing, f'{prefix}.read_latest.frame_age')}",
            ]
        )
    return " ".join(parts)


def _format_frame_timing(timing: dict[str, float], fps: float) -> str:
    action_source = _action_source_from_timing(timing, fps)
    loop_total = timing.get("loop.total", 0.0)
    parts = [
        "Rollout frame timing:",
        f"source={action_source}",
        f"loop={loop_total * 1000:.1f}ms",
        f"hz={(1 / loop_total) if loop_total > 0 else 0:.1f}/{fps:.1f}",
        f"obs={_ms(timing, 'robot.get_observation')}",
        f"motors={_ms(timing, 'robot.motors.sync_read')}",
        _format_camera_timing(timing),
        f"obs_proc={_ms(timing, 'observation_processor_and_notify')}",
        f"build={_ms(timing, 'action.build_dataset_frame')}",
        f"engine={_ms(timing, 'action.engine_get_action')}",
        f"inference={_ms(timing, 'inference.total')}",
        f"prepare={_ms(timing, 'inference.prepare_observation')}",
        f"pre={_ms(timing, 'inference.preprocessor')}",
        f"policy={_ms(timing, 'inference.policy_select_action')}",
        f"post={_ms(timing, 'inference.postprocessor')}",
        f"to_cpu={_ms(timing, 'inference.to_cpu')}",
        f"reorder={_ms(timing, 'inference.reorder_action')}",
        f"interp={_ms(timing, 'action.interpolator_get')}",
        f"act_proc={_ms(timing, 'action.robot_action_processor')}",
        f"send={_ms(timing, 'action.robot_send_action')}",
        f"telemetry={_ms(timing, 'telemetry')}",
    ]
    return " ".join(part for part in parts if part)


class BaseStrategy(RolloutStrategy):
    """Autonomous policy rollout with no data recording.

    All actions flow through the ``robot_action_processor`` pipeline
    before reaching the robot.
    """

    def setup(self, ctx: RolloutContext) -> None:
        """Initialise the inference engine."""
        self._init_engine(ctx)
        logger.info("Base strategy ready")

    def run(self, ctx: RolloutContext) -> None:
        """Run the autonomous control loop until shutdown or duration expires."""
        engine = self._engine
        cfg = ctx.runtime.cfg
        robot = ctx.hardware.robot_wrapper
        interpolator = self._interpolator

        control_interval = interpolator.get_control_interval(cfg.fps)
        timing_enabled = _env_flag("LEROBOT_ROLLOUT_TIMING")
        per_frame_timing_enabled = _env_flag("LEROBOT_ROLLOUT_TIMING_EVERY_FRAME")
        if timing_enabled:
            logger.info(
                "Rollout timing diagnostics enabled "
                "(set LEROBOT_ROLLOUT_TIMING=0 to disable; "
                "set LEROBOT_ROLLOUT_TIMING_SYNC_DEVICE=1 for synchronized CUDA/MPS policy timings; "
                "set LEROBOT_ROLLOUT_TIMING_EVERY_FRAME=1 for per-frame timing logs)"
            )

        start_time = time.perf_counter()
        engine.resume()
        logger.info("Base strategy control loop started")

        while not ctx.runtime.shutdown_event.is_set():
            loop_start = time.perf_counter()
            timing: dict[str, float] = {}

            if cfg.duration > 0 and (time.perf_counter() - start_time) >= cfg.duration:
                logger.info("Duration limit reached (%.0fs)", cfg.duration)
                break

            stage_start = time.perf_counter()
            obs = robot.get_observation()
            if timing_enabled:
                _record_timing(timing, "robot.get_observation", stage_start)
                _merge_robot_observation_timing(robot, timing)

            stage_start = time.perf_counter()
            obs_processed = self._process_observation_and_notify(ctx.processors, obs)
            if timing_enabled:
                _record_timing(timing, "observation_processor_and_notify", stage_start)

            if self._handle_warmup(cfg.use_torch_compile, loop_start, control_interval):
                continue

            action_dict = send_next_action(
                obs_processed,
                obs,
                ctx,
                interpolator,
                timing=timing if timing_enabled else None,
            )
            if timing_enabled and timing.get("action.engine_get_action", 0.0) > 0:
                timing.update(engine.last_timing)

            stage_start = time.perf_counter()
            self._log_telemetry(obs_processed, action_dict, ctx.runtime)
            if timing_enabled:
                _record_timing(timing, "telemetry", stage_start)

            dt = time.perf_counter() - loop_start
            if timing_enabled:
                timing["loop.total"] = dt
                if per_frame_timing_enabled:
                    logger.info(_format_frame_timing(timing, cfg.fps))

            if (sleep_t := control_interval - dt) > 0:
                precise_sleep(sleep_t)
            else:
                warning = (
                    f"Record loop is running slower ({1 / dt:.1f} Hz) than the target FPS ({cfg.fps} Hz). "
                    "Dataset frames might be dropped and robot control might be unstable. Common causes are: "
                    "1) Camera FPS not keeping up 2) Policy inference taking too long 3) CPU starvation"
                )
                if timing_enabled:
                    warning = f"{warning}. Timing breakdown: {_format_timing_breakdown(timing)}"
                logger.warning(warning)

    def teardown(self, ctx: RolloutContext) -> None:
        """Disconnect hardware and stop inference."""
        self._teardown_hardware(
            ctx.hardware,
            return_to_initial_position=ctx.runtime.cfg.return_to_initial_position,
        )
        logger.info("Base strategy teardown complete")
