lerobot-rollout \
  --strategy.type=base \
  --robot.type=so101_follower \
  --robot.port=/dev/tty.usbmodem5AE60533511 \
  --robot.cameras="{ front: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 25}}" \
  --robot.id=my_awesome_follower_arm \
  --display_data=false \
  --policy.device=cpu \
  --fps=8 \
  --task="put red ring into the box" \
  --duration=60 \
  --policy.path="./outputs/004000/pretrained_model" \
  --display_compressed_images=false

# Use sentry/highlight/dagger strategies if you want to record rollout data.
