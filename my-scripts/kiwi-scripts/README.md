# LeKiwi setup/test notes

Use the wheel-only sections when the LeKiwi mobile base is assembled but the arm is not connected yet.

Do not use the stock `lerobot-setup-motors --robot.type=lekiwi` path for a wheel-only build. That path expects the arm motors too.

## Port

Find the motor controller port first:

```bash
PORT=/dev/tty.usbmodem5B610338241
```

From repo root, commands use `./my-scripts/kiwi-scripts/...`.
From this directory, commands use `./kiwi-wheel-setup.sh` and `./kiwi-wheel-test.sh`.

## Optional scan

This checks which motor IDs are visible on the bus:

```bash
python my-scripts/kiwi-scripts/kiwi-wheel-only.py scan --port "$PORT"
```

If running from `my-scripts/kiwi-scripts`:

```bash
python ./kiwi-wheel-only.py scan --port "$PORT"
```

## One-time wheel ID setup

Connect exactly one wheel motor when prompted. Keep the arm disconnected.

Setup order:

1. Right wheel -> ID `9`
2. Back wheel -> ID `8`
3. Left wheel -> ID `7`

From repo root:

```bash
./my-scripts/kiwi-scripts/kiwi-wheel-setup.sh "$PORT"
```

From `my-scripts/kiwi-scripts`:

```bash
./kiwi-wheel-setup.sh "$PORT"
```

Expected prompts look like:

```text
Wheel-only LeKiwi setup
Connect exactly one wheel motor at a time. Leave the arm disconnected.

Target: base_right_wheel -> id 9
Connect ONLY this motor to the controller board, then press ENTER.
Set base_right_wheel to id 9
```

After setup finishes, reconnect all three wheel motors.

## Run the base smoke test

Lift the base off the table first so the wheels can spin freely.

From repo root:

```bash
./my-scripts/kiwi-scripts/kiwi-wheel-test.sh "$PORT"
```

From `my-scripts/kiwi-scripts`:

```bash
./kiwi-wheel-test.sh "$PORT"
```

Expected terminal output:

```text
Wheel IDs found. Starting low-speed test.

forward: body=(0.080, 0.000, 0.0) wheel_raw={...}
present_velocity={...}

backward: body=(-0.080, 0.000, 0.0) wheel_raw={...}
present_velocity={...}
...

Done. Wheels stopped.
```

Expected physical behavior:

- Each motion runs for about `0.7s`, then the script stops the wheels briefly.
- The test runs: `forward`, `backward`, `left`, `right`, `rotate_left`, `rotate_right`.
- The robot should move slowly if it is on the ground; while lifted, the wheel spin directions should change between motions.
- At the end, all wheel goal velocities are set to zero and torque is disabled.

To run only one or two motions:

```bash
python my-scripts/kiwi-scripts/kiwi-wheel-only.py test \
  --port "$PORT" \
  --motions forward rotate_left
```

To slow the test further:

```bash
python my-scripts/kiwi-scripts/kiwi-wheel-only.py test \
  --port "$PORT" \
  --speed 0.04 \
  --turn-speed 10 \
  --max-raw 400
```

## Jog one wheel

Use this if one wheel direction or ID seems wrong:

```bash
python my-scripts/kiwi-scripts/kiwi-wheel-only.py jog \
  --port "$PORT" \
  --wheel base_left_wheel \
  --raw 300 \
  --duration 0.5
```

Valid wheel names are:

- `base_left_wheel`
- `base_back_wheel`
- `base_right_wheel`

## Troubleshooting

If you see `Missing Python dependency 'tqdm'`, the script is not running inside the LeRobot dependency environment. Run from the repo environment, or install the LeKiwi dependencies:

```bash
uv sync --locked --extra lekiwi
```

If a motor ID is missing, rerun setup for that wheel with only that motor connected.

If the base moves in the wrong direction, first confirm the physical wheel positions match the setup order. Then use `jog` to verify each named wheel independently.

## Keyboard control

After wheel setup and the smoke test pass, you can control the wheel base from the keyboard.

Start with the base lifted. Put it on the floor only after the directions look correct.

From repo root:

```bash
./my-scripts/kiwi-scripts/kiwi-wheel-keyboard.sh "$PORT"
```

From `my-scripts/kiwi-scripts`:

```bash
./kiwi-wheel-keyboard.sh "$PORT"
```

Keys:

- `w`: forward
- `s`: backward
- `a`: left
- `d`: right
- `z`: rotate left
- `x`: rotate right
- `r`: speed up
- `f`: speed down
- `space`: stop
- `q`: quit

Expected terminal output:

```text
Keyboard control active. Lift the base first for initial testing.
w/s/a/d: move | z/x: rotate | r/f: speed up/down | space: stop | q: quit
Deadman timeout: 0.8s. Hold a key to keep moving.
Speed: 0.080 m/s, turn: 20.0 deg/s
```

The keyboard mode uses a deadman timeout by default: if it does not receive another motion key for about `0.8s`, it sends zero wheel velocity. Holding a movement key should keep the robot moving if your terminal has key repeat enabled. Press `space` any time to stop immediately.

To make keyboard control slower:

```bash
python my-scripts/kiwi-scripts/kiwi-wheel-only.py keyboard \
  --port "$PORT" \
  --speed 0.04 \
  --turn-speed 10 \
  --max-raw 400
```

To disable the deadman timeout and make movement latch until `space` or `q`:

```bash
python my-scripts/kiwi-scripts/kiwi-wheel-only.py keyboard \
  --port "$PORT" \
  --deadman-timeout 0
```

## Full wired LeKiwi calibration

Use this after the full LeKiwi robot is assembled: follower arm, wheel base, and separate leader arm.

For the wired version, run with cameras disabled first on macOS because the default LeKiwi camera paths are Linux paths like `/dev/video0`.

Calibrate the LeKiwi robot/base/follower board:

```bash
lerobot-calibrate \
  --robot.type=lekiwi \
  --robot.port="$ROBOT_PORT" \
  --robot.id=my_awesome_kiwi \
  --robot.cameras='{}'
```

Calibrate the leader arm separately:

```bash
lerobot-calibrate \
  --teleop.type=so100_leader \
  --teleop.port="$LEADER_PORT" \
  --teleop.id=my_awesome_leader_arm
```

The ports must be different:

- `ROBOT_PORT`: LeKiwi base/follower motor board.
- `LEADER_PORT`: separate SO100/SO101 leader arm board.

Use `lerobot-find-port` for each board. When prompted, unplug the board you are trying to identify.

## Full wired LeKiwi teleoperation

LeKiwi teleoperation uses two software roles even when everything is wired to one laptop.

The host owns the LeKiwi robot USB port and talks directly to the follower arm and wheel motors:

```bash
python -m lerobot.robots.lekiwi.lekiwi_host \
  --robot.id=my_awesome_kiwi \
  --robot.port="$ROBOT_PORT" \
  --robot.cameras='{}' \
  --host.connection_time_s=3600
```

The teleop client reads the leader arm and keyboard, then sends commands to the host over localhost:

```bash
LEKIWI_REMOTE_IP=127.0.0.1 \
LEKIWI_ROBOT_ID=my_awesome_kiwi \
LEKIWI_LEADER_PORT="$LEADER_PORT" \
LEKIWI_LEADER_ID=my_awesome_leader_arm \
LEKIWI_DISABLE_CAMERAS=1 \
python examples/lekiwi/teleoperate.py
```

The data flow is:

```text
leader arm + keyboard
        -> examples/lekiwi/teleoperate.py
        -> ZMQ on localhost:5555/5556
        -> lekiwi_host
        -> USB serial
        -> LeKiwi follower arm + wheels
```

The repeated host warning `No command available` is normal before the client starts. The watchdog stops the base if commands stop arriving for more than `500ms`.

Control keys:

- Hold `w`: forward
- Hold `s`: backward
- Hold `a`: left
- Hold `d`: right
- Hold `z`: rotate left
- Hold `x`: rotate right
- Press `r`: speed up
- Press `f`: speed down

Move the physical leader arm to move the follower arm. Start with the base lifted for the first test.

## One-command local launcher

After both the LeKiwi robot and leader arm are calibrated, this helper starts the host in the background and then starts the teleop client:

```bash
./my-scripts/kiwi-scripts/lekiwi-local-teleop.sh "$ROBOT_PORT" "$LEADER_PORT"
```

Or with environment variables:

```bash
KIWI_ROBOT_PORT=/dev/tty.usbmodem5B610338241 \
KIWI_LEADER_PORT=/dev/tty.usbmodem5AE60574511 \
./my-scripts/kiwi-scripts/lekiwi-local-teleop.sh

KIWI_ROBOT_PORT=/dev/tty.usbmodem5B610338241 \
KIWI_LEADER_PORT=/dev/tty.usbmodem5AE60574511 \
./lekiwi-local-teleop.sh

```

Optional overrides:

```bash
KIWI_ROBOT_ID=my_awesome_kiwi
KIWI_LEADER_ID=my_awesome_leader_arm
KIWI_HOST_TIME_S=3600
```

The launcher sends one newline to the host so it uses the saved robot calibration file automatically. If the robot has not been calibrated yet, run the calibration command first.

## Raspberry Pi LeKiwi teleoperation

For the Pi-mounted robot, the laptop runs the leader arm + keyboard client, and the Raspberry Pi runs the LeKiwi host that owns the robot USB port.

One command starts the host over SSH, waits for the host ports, then starts the local teleop client:

```bash
./my-scripts/kiwi-scripts/lekiwi-pi-teleop.sh
```

Current defaults:

```bash
KIWI_LEADER_PORT=/dev/tty.usbmodem5AE60574511
KIWI_PI_USER=robot
KIWI_PI_HOST=pi5-robot.local
KIWI_PI_REPO_DIR=/home/robot/dev/lerobot
KIWI_PI_PYTHON=/home/robot/miniforge3/envs/lerobot-fork/bin/python
KIWI_ROBOT_PORT=/dev/ttyACM0
KIWI_LOCAL_CONDA_ENV=lerobot-fork
KIWI_ENABLE_CAMERAS=0
KIWI_FRONT_CAMERA_PATH=/dev/video0
KIWI_WRIST_CAMERA_PATH=/dev/video2
KIWI_CAMERA_FOURCC=MJPG
KIWI_CAMERA_BACKEND=200
KIWI_STOP_EXISTING_HOST=1
KIWI_ROBOT_ID=my_awesome_kiwi
KIWI_LEADER_ID=my_awesome_leader_arm
KIWI_HOST_TIME_S=3600
```

If your Pi uses a different checkout or Python environment, override the paths:

```bash
KIWI_PI_REPO_DIR=/home/robot/dev/lerobot \
KIWI_PI_PYTHON=/home/robot/miniforge3/envs/lerobot/bin/python \
./my-scripts/kiwi-scripts/lekiwi-pi-teleop.sh
```

The launcher requires key-based SSH because it starts the remote host non-interactively and stops it when teleop exits:

```bash
ssh robot@pi5-robot.local
ssh-copy-id robot@pi5-robot.local
```

If a previous run left `lekiwi_host` running on the Pi, it can keep ZMQ ports and camera devices open. The launcher stops existing `lerobot.robots.lekiwi.lekiwi_host` processes by default before starting a new one. To disable that behavior:

```bash
KIWI_STOP_EXISTING_HOST=0 ./my-scripts/kiwi-scripts/lekiwi-pi-teleop.sh
```

The signal flow is:

```text
Mac laptop
  leader arm USB + keyboard
        |
        v
  examples/lekiwi/teleoperate.py
        |
        |  ZMQ PUSH actions on tcp://pi5-robot.local:5555
        |  ZMQ PULL observations on tcp://pi5-robot.local:5556
        v
Raspberry Pi
  lerobot.robots.lekiwi.lekiwi_host
        |
        |  USB serial /dev/ttyACM0
        v
LeKiwi robot
  follower arm + wheel base
```

The two network channels are ZeroMQ sockets:

- `5555`: laptop client pushes action messages to the Pi host.
- `5556`: Pi host pushes observation messages back to the laptop client.

Both sockets use `ZMQ_CONFLATE`, so they behave like a one-item latest-value queue rather than an ever-growing queue. If messages arrive faster than the receiver reads them, older queued messages are dropped and only the newest command or observation is kept. This is intentional for teleoperation because stale robot commands are worse than skipped intermediate commands.

The Pi host also has a watchdog. If no command is received for more than `500ms`, it stops the mobile base.

### ROS2 setup for Pi 3 / Pi 5 nodes

Use this when preparing Raspberry Pi nodes for the ROS2 LeKiwi bridge. The
scripts assume Ubuntu 24.04 64-bit with user `robot`.

For a fresh Pi, copy and run the full bootstrap from your Mac:

```bash
cd /Users/rdolgov/code/so101/fork/rdolgov/lerobot

# Defaults to robot@pi3-robot.local.
./my-scripts/kiwi-scripts/setup-lekiwi-ros2-remote.sh

# Or choose a target explicitly:
LEKIWI_REMOTE=robot@pi5-robot.local \
./my-scripts/kiwi-scripts/setup-lekiwi-ros2-remote.sh
```

This installs ROS2 Jazzy, clones/updates `https://github.com/rdolgov/lerobot`
into `~/dev/fork/rdolgov/lerobot`, creates `~/ros2_lerobot_venv`, writes the
`lekiwi_ros_bridge` ROS2 package, and builds it in `~/ros2_ws`.

If you are already SSH'd into the Pi and the repo exists there, run the Pi-local
bootstrap directly:

```bash
cd ~/dev/fork/rdolgov/lerobot
./my-scripts/kiwi-scripts/setup-lekiwi-ros2-pi.sh
```

After Pi 3 and Pi 5 both have the ROS2 workspace, install the same common ROS2
environment on both nodes from your Mac:

```bash
cd /Users/rdolgov/code/so101/fork/rdolgov/lerobot
./my-scripts/kiwi-scripts/update-lekiwi-ros2-env-remote.sh
```

That updates both default targets:

```text
robot@pi3-robot.local
robot@pi5-robot.local
```

To update only one node:

```bash
./my-scripts/kiwi-scripts/update-lekiwi-ros2-env-remote.sh robot@pi3-robot.local
./my-scripts/kiwi-scripts/update-lekiwi-ros2-env-remote.sh robot@pi5-robot.local
```

The env updater creates `~/ros2_lekiwi_env.sh` on each Pi and adds a guarded
`.bashrc` hook. It sets a common ROS domain and sources ROS2, the LeRobot venv,
and the ROS2 workspace:

```bash
export ROS_DOMAIN_ID=23
unset ROS_LOCALHOST_ONLY
source /opt/ros/jazzy/setup.bash
source ~/ros2_lerobot_venv/bin/activate
source ~/ros2_ws/install/setup.bash
```

In an existing SSH terminal, reload it with:

```bash
source ~/ros2_lekiwi_env.sh
```

Quick mock-mode test:

```bash
# Terminal 1, on one Pi:
source ~/ros2_lekiwi_env.sh
ros2 run lekiwi_ros_bridge lekiwi_host_node --ros-args -p mock:=true

# Terminal 2, on the other Pi:
source ~/ros2_lekiwi_env.sh
ros2 topic list -t
ros2 node list
ros2 run lekiwi_ros_bridge observation_echo
```

If nodes are not visible across machines, verify both terminals report the same
domain:

```bash
echo "$ROS_DOMAIN_ID"
echo "${ROS_LOCALHOST_ONLY:-unset}"
ros2 multicast send
ros2 multicast receive
```

### Camera view in Rerun

By default, the launcher disables cameras because it is the fastest smoke-test path. To see the Pi cameras in Rerun, enable cameras:

```bash
KIWI_ENABLE_CAMERAS=1 ./my-scripts/kiwi-scripts/lekiwi-pi-teleop.sh
```

This starts the Pi host with two tested USB camera configs, matching the normal LeKiwi `front` + `wrist` setup:

- `front`: `/dev/video0`, 640x480, 30 FPS
- `wrist`: `/dev/video2`, output 480x640, 30 FPS, rotated 90 degrees
- `fourcc`: `MJPG`
- `backend`: `200` (`cv2.CAP_V4L2`)

Those settings matter on the Raspberry Pi. On this Pi, `/dev/video0` and `/dev/video2` are the real USB webcam capture nodes. `/dev/video1` and `/dev/video3` are UVC metadata nodes, not camera streams. The launcher replaces the default LeKiwi camera config with explicit V4L2/MJPG settings for both cameras when `KIWI_ENABLE_CAMERAS=1`.

The Pi reads the camera frames, JPEG-encodes them, and sends them over the observation ZMQ channel on port `5556`. The laptop decodes them and `examples/lekiwi/teleoperate.py` logs them to the Rerun viewer as image observations.

Camera overrides:

```bash
KIWI_ENABLE_CAMERAS=1 \
KIWI_FRONT_CAMERA_PATH=/dev/video0 \
KIWI_FRONT_CAMERA_WIDTH=640 \
KIWI_FRONT_CAMERA_HEIGHT=480 \
KIWI_FRONT_CAMERA_ROTATION=0 \
KIWI_WRIST_CAMERA_PATH=/dev/video2 \
KIWI_WRIST_CAMERA_WIDTH=480 \
KIWI_WRIST_CAMERA_HEIGHT=640 \
KIWI_WRIST_CAMERA_ROTATION=90 \
KIWI_CAMERA_FOURCC=MJPG \
KIWI_CAMERA_BACKEND=200 \
./my-scripts/kiwi-scripts/lekiwi-pi-teleop.sh
```

To run only one camera:

```bash
KIWI_ENABLE_CAMERAS=1 KIWI_ENABLE_WRIST_CAMERA=0 ./my-scripts/kiwi-scripts/lekiwi-pi-teleop.sh
KIWI_ENABLE_CAMERAS=1 KIWI_ENABLE_FRONT_CAMERA=0 ./my-scripts/kiwi-scripts/lekiwi-pi-teleop.sh
```

If camera startup fails, verify the devices on the Pi:

```bash
ssh robot@pi5-robot.local 'ls -l /dev/video*'
ssh robot@pi5-robot.local 'v4l2-ctl --list-devices'
ssh robot@pi5-robot.local 'v4l2-ctl --device=/dev/video0 --list-formats-ext'
ssh robot@pi5-robot.local 'v4l2-ctl --device=/dev/video2 --list-formats-ext'
```

If the camera devices are different, override `KIWI_FRONT_CAMERA_PATH` or `KIWI_WRIST_CAMERA_PATH`, or use the smoke-test mode without cameras:

```bash
KIWI_ENABLE_CAMERAS=0 ./my-scripts/kiwi-scripts/lekiwi-pi-teleop.sh
```

The default no-camera script does the same work you would do manually:

```bash
# On the Pi, started through SSH by the launcher:
cd /home/robot/dev/lerobot
PYTHONPATH=/home/robot/dev/lerobot/src \
/home/robot/miniforge3/envs/lerobot-fork/bin/python \
  -m lerobot.robots.lekiwi.lekiwi_host \
  --robot.id=my_awesome_kiwi \
  --robot.port=/dev/ttyACM0 \
  --robot.cameras='{}' \
  --host.connection_time_s=3600

# On the laptop, started after the Pi ports are reachable:
LEKIWI_REMOTE_IP=pi5-robot.local \
LEKIWI_LEADER_PORT=/dev/tty.usbmodem5AE60574511 \
LEKIWI_DISABLE_CAMERAS=1 \
/Users/rdolgov/miniforge3/envs/lerobot-fork/bin/python examples/lekiwi/teleoperate.py
```

With `KIWI_ENABLE_CAMERAS=1`, the launcher omits `--robot.cameras='{}'` on the Pi and sends `LEKIWI_DISABLE_CAMERAS=0` to the laptop client.

Troubleshooting:

- `cd: /home/robot/lerobot: No such file or directory`: use `KIWI_PI_REPO_DIR=/home/robot/dev/lerobot`.
- `ModuleNotFoundError: No module named 'zmq'`: use the `lerobot-fork` conda env or set `KIWI_LOCAL_PYTHON=/Users/rdolgov/miniforge3/envs/lerobot-fork/bin/python`.
- `Timed out waiting for frame from camera OpenCVCamera(/dev/video0)`: use `KIWI_ENABLE_CAMERAS=1` with the launcher defaults, which force `backend=200` and `fourcc=MJPG`.
- `Device or resource busy`: check for a stale camera process with `ssh robot@pi5-robot.local 'fuser -v /dev/video0 /dev/video2'`. The launcher normally clears stale `lekiwi_host` processes automatically with `KIWI_STOP_EXISTING_HOST=1`.
- `Timeout waiting for LeKiwi host ports`: check the Pi host output above the timeout; the host may have failed to open `/dev/ttyACM0` or may be using different ZMQ ports.
- `Permission denied`: confirm key-based SSH with `ssh robot@pi5-robot.local true`.

If the LeKiwi host is already running on the Pi, you can run only the laptop client:

```bash
LEKIWI_REMOTE_IP=pi5-robot.local \
LEKIWI_LEADER_PORT="$LEADER_PORT" \
LEKIWI_DISABLE_CAMERAS=1 \
/Users/rdolgov/miniforge3/envs/lerobot-fork/bin/python examples/lekiwi/teleoperate.py
```
