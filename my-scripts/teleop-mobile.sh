lerobot-teleoperate \
    --robot.type=so101_follower \
    --robot.port=/dev/tty.usbmodem5B610340181 \
    --robot.id=my_awesome_mobile_arm \
    --robot.cameras="{ top: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 25}, front: {type: opencv, index_or_path: 1, width: 640, height: 480, fps: 25}}" \
    --teleop.type=so101_leader \
    --teleop.port=/dev/tty.usbmodem5AE60574511 \
    --teleop.id=my_awesome_leader_arm \
    --display_data=true