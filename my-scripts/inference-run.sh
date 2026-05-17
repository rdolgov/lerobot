lerobot-rollout \
  --strategy.type=base \
  --robot.type=so101_follower \
  --robot.port=/dev/tty.usbmodem5AE60533511 \
  --robot.cameras="{ top: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 25}, front: {type: opencv, index_or_path: 1, width: 640, height: 480, fps: 25}}" \
  --robot.id=my_awesome_follower_arm \
  --display_data=true \
  --policy.device=cpu \
  --fps=5 \
  --task="put red ring into the box" \
  --duration=60 \
  --policy.path=romando/act-so101-test-may15-2300 \
  --display_compressed_images=false

# Use sentry/highlight/dagger strategies if you want to record rollout data.
