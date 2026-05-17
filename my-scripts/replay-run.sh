#!/usr/bin/env bash
set -euo pipefail

# Change these two values to choose which recorded dataset episode to replay.
RECORDING_SET="record-test-may16-1200_20260516_124636"
EPISODE_NUMBER="0"

: "${HF_USER:?Set HF_USER first, for example: export HF_USER=romando}"

lerobot-replay \
    --robot.type=so101_follower \
    --robot.port=/dev/tty.usbmodem5AE60533511 \
    --robot.id=my_awesome_follower_arm \
    --dataset.repo_id="${HF_USER}/${RECORDING_SET}" \
    --dataset.episode="${EPISODE_NUMBER}"
