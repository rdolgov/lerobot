lerobot-teleoperate \
  --robot.type=so101_follower \
  --robot.port=/dev/tty.usbmodem5AE60533511 \
  --robot.id=my_awesome_follower_arm \
  --robot.disable_torque_on_disconnect=false \
  --teleop.type=so101_leader \
  --teleop.port=/dev/tty.usbmodem5AE60574511 \
  --teleop.id=my_awesome_leader_arm \
  --fps=60 \
  --display_data=false