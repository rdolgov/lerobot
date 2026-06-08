# Wheel-only LeKiwi base setup/test

Use this when the LeKiwi mobile base is assembled but the arm is not connected yet.

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
