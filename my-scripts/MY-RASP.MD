The port of this MotorsBus is '/dev/ttyACM0'

conda activate lerobot-fork


ssh robot@pi5-robot.local 'mkdir -p ~/.cache/huggingface/lerobot/calibration/robots/lekiwi'

scp ~/.cache/huggingface/lerobot/calibration/robots/lekiwi/my_awesome_kiwi.json \
  robot@pi5-robot.local:~/.cache/huggingface/lerobot/calibration/robots/lekiwi/


# Teleop 

```
  python -m lerobot.robots.lekiwi.lekiwi_host \
    --robot.id=my_awesome_kiwi \
    --robot.cameras='{"front":{"type":"opencv","index_or_path":"/dev/video0","width":640, "height":480,"fps":30,"fourcc":"MJPG","warmup_s":5,"rotation":180}}'
  ```