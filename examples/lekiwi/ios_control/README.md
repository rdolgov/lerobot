# LeKiwi iPhone Control

This is a first iOS control surface for the ROS2 LeKiwi bridge.

The phone does not speak ROS2/DDS directly. Instead:

```text
iPhone SwiftUI app
  WebSocket JSON
        |
        v
ROS2 WebSocket bridge on Pi/Ubuntu
  publishes /lekiwi/action
  subscribes /lekiwi/observation
        |
        v
lekiwi_host_node
  talks to LeRobot LeKiwi hardware
```

This keeps the phone app simple and lets ROS2 discovery stay on the robot
network.

## 1. Start the LeKiwi ROS2 host

On the robot Pi:

```bash
source ~/ros2_lekiwi_env.sh

# Safe first run:
ros2 run lekiwi_ros_bridge lekiwi_host_node --ros-args -p mock:=true
```

For the real robot, start with wheels lifted and cameras disabled:

```bash
source ~/ros2_lekiwi_env.sh
ros2 run lekiwi_ros_bridge lekiwi_host_node --ros-args \
  -p mock:=false \
  -p robot_id:=my_awesome_kiwi \
  -p port:=/dev/ttyACM0 \
  -p disable_cameras:=true
```

Keep `disable_cameras:=true` when using the separate camera publisher below.
That avoids two processes fighting over `/dev/video*`.

## 2. Start the camera publisher

On the Pi that owns the mobile-base cameras:

```bash
source ~/ros2_lekiwi_env.sh
cd ~/dev/fork/rdolgov/lerobot
sudo apt install ros-jazzy-sensor-msgs
python examples/lekiwi/ios_control/ros2_camera_publisher.py
```

It publishes standard ROS2 compressed image topics:

```text
/lekiwi/front/image/compressed
/lekiwi/wrist/image/compressed
```

Useful overrides:

```bash
python examples/lekiwi/ios_control/ros2_camera_publisher.py \
  --front-path /dev/video0 \
  --wrist-path /dev/video2 \
  --front-rotation 0 \
  --wrist-rotation 90 \
  --publish-fps 10 \
  --jpeg-quality 80
```

## 3. Start the WebSocket bridge

On any machine that can see the LeKiwi ROS2 topics, usually the same Pi:

```bash
source ~/ros2_lekiwi_env.sh
python -m pip install websockets

cd ~/dev/fork/rdolgov/lerobot
python examples/lekiwi/ios_control/ros2_websocket_bridge.py \
  --host 0.0.0.0 \
  --port 8765
```

Check from another terminal:

```bash
source ~/ros2_lekiwi_env.sh
ros2 topic list -t
ros2 node list
```

You should see:

```text
/lekiwi/action [std_msgs/msg/String]
/lekiwi/observation [std_msgs/msg/String]
/lekiwi/front/image/compressed [sensor_msgs/msg/CompressedImage]
/lekiwi/wrist/image/compressed [sensor_msgs/msg/CompressedImage]
/lekiwi_ios_websocket_bridge
```

The WebSocket bridge subscribes to the compressed image topics and forwards the
latest JPEGs to the iPhone as base64 fields named `front` and `wrist`.

## 4. Open the iOS app

On your Mac:

```bash
open examples/lekiwi/ios_control/LeKiwiControl/LeKiwiControl.xcodeproj
```

In Xcode:

1. Select the `LeKiwiControl` target.
2. Set your Team under Signing & Capabilities.
3. Choose your iPhone or an iOS simulator.
4. Build and run.

On first launch, iOS may ask for Local Network permission. Allow it.

## 5. Connect from the phone

Use the bridge machine hostname or IP:

```text
ws://pi5-robot.local:8765
ws://pi3-robot.local:8765
ws://192.168.1.47:8765
```

Tap **Connect**. Hold movement buttons to send repeated commands:

- Forward/back: `x.vel`
- Left/right: `y.vel`
- Turn L/R: `theta.vel`
- Stop: zero command

The app sends commands every `0.1s` while a button is held and sends stop on
release. The WebSocket bridge also publishes a stop command if phone commands
stop for more than `0.5s`.

## Troubleshooting

If the phone cannot connect:

```bash
hostname -I
ss -ltnp | grep 8765
```

Use the IP address from `hostname -I` in the app URL.

If the app connects but no image appears:

- Run `ros2_camera_publisher.py` on the Pi with the cameras.
- Confirm `/lekiwi/front/image/compressed` or `/lekiwi/wrist/image/compressed` exists.
- Confirm camera devices are free on the Pi.
- Use `ros2 topic hz /lekiwi/front/image/compressed` to check frame rate.

If controls do not move the mock observation:

```bash
source ~/ros2_lekiwi_env.sh
ros2 topic echo /lekiwi/action --qos-reliability best_effort
```

Then press a button in the app. You should see JSON with `x.vel`, `y.vel`, or
`theta.vel`.

For first real-robot testing, lift the wheels and keep the physical power switch
within reach.
