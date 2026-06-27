# LeKiwi ROS 2 Workspace

This workspace contains a small ROS 2 bridge for running LeKiwi through ROS topics.

- `lekiwi_host_node` connects to the robot, subscribes to `/lekiwi/action`, and publishes `/lekiwi/observation`.
- `action_publisher` publishes simple base velocity commands.
- `observation_echo` prints a compact observation summary once per second.

The scripts in `scripts/` source ROS, activate the LeRobot virtualenv, and source this workspace for you.

## Expected Setup

Defaults used by the scripts:

- ROS distro: `jazzy`
- LeRobot virtualenv: `~/ros2_lerobot_venv`
- Robot serial port: `/dev/ttyACM0`
- Robot id: `my_awesome_kiwi`

You can override these with environment variables:

```bash
export ROS_DISTRO=jazzy
export LEROBOT_VENV=~/ros2_lerobot_venv
export ROBOT_ID=my_awesome_kiwi
export LEKIWI_PORT=/dev/ttyACM0
```

## Build

From this `ros2_ws` folder:

```bash
./scripts/build.sh
```

The build script intentionally uses:

```bash
python -m colcon build --symlink-install --packages-select lekiwi_ros_bridge
```

This keeps the generated ROS entry points tied to the active LeRobot virtualenv Python.

## Run In Three Terminals

Terminal 1, robot host:

```bash
./scripts/terminal1_host.sh
```

Terminal 2, action publisher:

```bash
./scripts/terminal2_action_publisher.sh
```

Terminal 3, observation echo:

```bash
./scripts/terminal3_observation_echo.sh
```

The first host warning is normal until commands arrive:

```text
No recent command; stopping base
```

## Run In Mock Mode

Mock mode is useful for checking ROS wiring without hardware:

```bash
MOCK=true ./scripts/terminal1_host.sh
./scripts/terminal2_action_publisher.sh
./scripts/terminal3_observation_echo.sh
```

## Command Parameters

Host script variables:

```bash
MOCK=false
ROBOT_ID=my_awesome_kiwi
LEKIWI_PORT=/dev/ttyACM0
DISABLE_CAMERAS=true
MAX_LOOP_FREQ_HZ=30.0
WATCHDOG_TIMEOUT_MS=500.0
```

Action publisher variables:

```bash
RATE_HZ=5.0
X_VEL=0.0
Y_VEL=0.0
THETA_VEL=0.0
```

Example:

```bash
X_VEL=0.02 RATE_HZ=10 ./scripts/terminal2_action_publisher.sh
```

## Open All Three With tmux

If `tmux` is installed:

```bash
./scripts/run_all_tmux.sh
```

For mock mode:

```bash
MOCK=true ./scripts/run_all_tmux.sh
```

Attach later with:

```bash
tmux attach -t lekiwi_ros
```

