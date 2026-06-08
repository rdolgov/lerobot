 Had issues with running using 'default' script, applying values below made it better.
 
 Most likely causes, in order:

  1. Task text mismatch
     Your cached training dataset task is Grab the red ring may 16, but my-scripts/inference-run-smolvla.sh:14 uses put red ring into the box.

     ACT effectively ignores task language. SmolVLA tokenizes and conditions on it. Try the exact training task string first:

     --task="Grab the red ring may 16"

  2. FPS mismatch
     The dataset metadata says fps: 30, while your rollout currently uses --fps=25. SmolVLA predicts 50-step chunks, so timing errors stretch the trajectory more than
     ACT’s 25-step chunks. Try matching training:

     --fps=30

  3. SmolVLA is executing longer open-loop chunks
     Cached configs show:
      - ACT: chunk_size=25, n_action_steps=25
      - SmolVLA: chunk_size=50, n_action_steps=50

     At 25 Hz, SmolVLA commits to about 2 seconds of actions before replanning. That can easily look like “almost right, but a bit low at drop.” For sync inference, try
     replanning more often:

     --policy.n_action_steps=10

  4. Use RTC for SmolVLA
     Your script uses default sync inference. SmolVLA is a flow-matching VLA and the repo docs specifically point RTC at SmolVLA-like policies. Try:

     --inference.type=rtc \
     --inference.rtc.execution_horizon=10 \
     --inference.rtc.max_guidance_weight=10.0 \
     --inference.rtc.prefix_attention_schedule=EXP

  A first concrete SmolVLA experiment would be: exact training task string, --fps=30, and RTC enabled. Do not reduce FPS to make inference “easier”; that changes the
  learned action timing.

  For debugging, record one ACT rollout and one SmolVLA rollout with --strategy.type=sentry or enable --display_data=true, then compare shoulder_lift.pos,
  elbow_flex.pos, and wrist_flex.pos around pickup/drop. If SmolVLA’s commanded joints are already lower than ACT before sending to the robot, it is model/training/
  inference conditioning. If commands look similar but achieved state is lower, then look at timing, servo lag, or clipping.

  Also: “better pretrained model” does not mean better on a tiny, fixed single-task setup. ACT often wins on precise single-task memorization. Your SmolVLA checkpoint
  name suggests 5k steps; for SmolVLA that may still be undertrained unless the dataset is very clean. The repo guide also notes SmolVLA often improves a lot with:

  --policy.freeze_vision_encoder=false \
  --policy.train_expert_only=false

─ Worked for 7m 22s ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────


› apply recommendations to my-scripts/inference-run-smolvla.sh


• I’ll update the SmolVLA rollout script to match the training task text and dataset FPS, and switch SmolVLA to RTC inference with the recommended overlap settings.

• Explored
  └ Read inference-run-smolvla.sh

• Ran git status --short my-scripts/inference-run-smolvla.sh
  └ ?? my-scripts/inference-run-smolvla.sh

─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

• The script is untracked, so I’ll only patch this file and leave the rest of the worktree alone. I’m keeping camera capture at 25 FPS for now but setting rollout
  control to 30 FPS to match the recorded dataset metadata; if the cameras cannot sustain it, the timing logs will make that obvious.

• Edited my-scripts/inference-run-smolvla.sh (+6 -2)
     6    --strategy.type=base \
     7 +  --inference.type=rtc \
     8 +  --inference.rtc.execution_horizon=10 \
     9 +  --inference.rtc.max_guidance_weight=10.0 \
    10 +  --inference.rtc.prefix_attention_schedule=EXP \
    11    --robot.type=so101_follower \
       ⋮
    16    --policy.device=mps \
    13 -  --fps=25 \
    14 -  --task="put red ring into the box" \
    17 +  --fps=30 \
    18 +  --task="Grab the red ring may 16" \
    19    --duration=60 \

• Explored
  └ Read inference-run-smolvla.sh

• Ran git diff -- my-scripts/inference-run-smolvla.sh
  └ (no output)

─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

• The patch is in place. I’m doing a lightweight shell syntax check now; I won’t run the rollout because that would connect to the robot.

• Ran zsh -n my-scripts/inference-run-smolvla.sh
  └ (no output)

─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

• Updated my-scripts/inference-run-smolvla.sh:1.

  Changes:

  - Enabled RTC inference for SmolVLA.
  - Added execution_horizon=10, max_guidance_weight=10.0, prefix_attention_schedule=EXP.
  - Changed rollout --fps from 25 to 30.
  - Changed task text to the training dataset task: Grab the red ring may 16.

  Validation: zsh -n my-scripts/inference-run-smolvla.sh passed. I did not run the rollout, since that would connect to the robot.

──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 