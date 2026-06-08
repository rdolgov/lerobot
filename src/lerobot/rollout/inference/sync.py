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

"""Synchronous inference engine: inline policy call per control tick."""

from __future__ import annotations

import logging
import os
import time
from contextlib import nullcontext
from copy import copy

import torch

from lerobot.policies.pretrained import PreTrainedPolicy
from lerobot.policies.utils import make_robot_action, prepare_observation_for_inference
from lerobot.processor import PolicyProcessorPipeline

from .base import InferenceEngine

logger = logging.getLogger(__name__)


def _env_flag(name: str) -> bool:
    return os.environ.get(name, "").lower() in {"1", "true", "yes", "on"}


def _sync_device_for_timing(device: torch.device) -> None:
    if not (_env_flag("LEROBOT_ROLLOUT_TIMING") and _env_flag("LEROBOT_ROLLOUT_TIMING_SYNC_DEVICE")):
        return
    if device.type == "cuda" and torch.cuda.is_available():
        torch.cuda.synchronize(device)
    elif (
        device.type == "mps"
        and hasattr(torch, "mps")
        and hasattr(torch.mps, "synchronize")
        and hasattr(torch.backends, "mps")
        and torch.backends.mps.is_available()
    ):
        torch.mps.synchronize()


# TODO(Steven): support relative-action policies.  The per-tick flow refreshes
# ``RelativeActionsProcessorStep._last_state`` every call, so cached chunk
# actions popped on later ticks get reanchored to the *current* robot state and
# absolute targets drift through the chunk.  Relative-action policies are
# rejected at context-build time today; RTC postprocesses the whole chunk and
# is unaffected.
#
# Candidate fix: drive the policy via ``predict_action_chunk`` and serve a
# local FIFO of postprocessed actions.  Eliminates drift by construction and
# saves per-tick pre/post work, but bypasses ``select_action`` — needs
# fallbacks for SAC (raises), ACT temporal ensembling (ensembler lives in
# ``select_action``), and Diffusion-family (obs-history queues populated as a
# side effect of ``select_action``).


class SyncInferenceEngine(InferenceEngine):
    """Inline synchronous inference: compute one action per call.

    ``get_action`` runs the full policy pipeline (pre/post-processor +
    ``select_action``) on the given observation frame and returns a
    CPU action tensor reordered to match the dataset action keys.
    """

    def __init__(
        self,
        policy: PreTrainedPolicy,
        preprocessor: PolicyProcessorPipeline,
        postprocessor: PolicyProcessorPipeline,
        dataset_features: dict,
        ordered_action_keys: list[str],
        task: str,
        device: str | None,
        robot_type: str,
    ) -> None:
        self._policy = policy
        self._preprocessor = preprocessor
        self._postprocessor = postprocessor
        self._dataset_features = dataset_features
        self._ordered_action_keys = ordered_action_keys
        self._task = task
        self._device = torch.device(device or "cpu")
        self._robot_type = robot_type
        self._last_timing: dict[str, float] = {}
        logger.info(
            "SyncInferenceEngine initialized (device=%s, action_keys=%d)",
            self._device,
            len(ordered_action_keys),
        )

    def start(self) -> None:
        """No background resources to start."""
        logger.info("SyncInferenceEngine started (inline mode — no background thread)")

    def stop(self) -> None:
        """No background resources to stop."""
        logger.info("SyncInferenceEngine stopped")

    def reset(self) -> None:
        """Reset the policy and pre/post-processors."""
        logger.info("Resetting sync inference state (policy + processors)")
        self._policy.reset()
        self._preprocessor.reset()
        self._postprocessor.reset()
        self._last_timing = {}

    @property
    def last_timing(self) -> dict[str, float]:
        """Timings from the most recent synchronous inference call, in seconds."""
        return self._last_timing.copy()

    def get_action(self, obs_frame: dict | None) -> torch.Tensor | None:
        """Run the full inference pipeline on ``obs_frame`` and return an action tensor."""
        if obs_frame is None:
            self._last_timing = {}
            return None
        # Shallow copy is intentional: the caller (`send_next_action`) builds
        # ``obs_frame`` fresh per tick via ``build_dataset_frame``, so the
        # tensor/array values are not shared with any other reader.
        observation = copy(obs_frame)
        autocast_ctx = (
            torch.autocast(device_type=self._device.type)
            if self._device.type == "cuda" and self._policy.config.use_amp
            else nullcontext()
        )
        timings: dict[str, float] = {}

        def record_stage(name: str, start: float) -> None:
            _sync_device_for_timing(self._device)
            timings[f"inference.{name}"] = time.perf_counter() - start

        total_start = time.perf_counter()
        with torch.inference_mode(), autocast_ctx:
            stage_start = time.perf_counter()
            observation = prepare_observation_for_inference(
                observation, self._device, self._task, self._robot_type
            )
            record_stage("prepare_observation", stage_start)

            stage_start = time.perf_counter()
            observation = self._preprocessor(observation)
            record_stage("preprocessor", stage_start)

            stage_start = time.perf_counter()
            action = self._policy.select_action(observation)
            record_stage("policy_select_action", stage_start)

            stage_start = time.perf_counter()
            action = self._postprocessor(action)
            record_stage("postprocessor", stage_start)

        stage_start = time.perf_counter()
        action_tensor = action.squeeze(0).cpu()
        record_stage("to_cpu", stage_start)

        # Reorder to match dataset action ordering so the caller can treat
        # the returned tensor uniformly across backends.
        stage_start = time.perf_counter()
        action_dict = make_robot_action(action_tensor, self._dataset_features)
        ordered_action = torch.tensor([action_dict[k] for k in self._ordered_action_keys])
        timings["inference.reorder_action"] = time.perf_counter() - stage_start
        timings["inference.total"] = time.perf_counter() - total_start
        self._last_timing = timings
        return ordered_action
