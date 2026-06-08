PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}src" \
LEROBOT_ROLLOUT_TIMING=1 \
LEROBOT_ROLLOUT_TIMING_EVERY_FRAME=1 \
LEROBOT_ROLLOUT_TIMING_SYNC_DEVICE=0 \
lerobot-rollout \
  --strategy.type=base \
  --inference.type=rtc \
  --inference.rtc.execution_horizon=10 \
  --inference.rtc.max_guidance_weight=10.0 \
  --inference.rtc.prefix_attention_schedule=EXP \
  --robot.type=so101_follower \
  --robot.port=/dev/tty.usbmodem5B610340181\
  --robot.cameras="{ top: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 25}, front: {type: opencv, index_or_path: 1, width: 640, height: 480, fps: 25}}" \
  --robot.id=my_awesome_mobile_arm \
  --display_data=false \
  --policy.device=mps \
  --fps=30 \
  --task="Grab the red ring may 16" \
  --duration=60 \
  --policy.path=romando/smolvla-so101-5000stepB \
  --display_compressed_images=false

# Use sentry/highlight/dagger strategies if you want to record rollout data.
