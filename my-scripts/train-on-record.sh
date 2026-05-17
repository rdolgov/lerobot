lerobot-train \
  --dataset.repo_id="${HF_USER}"/record-test-may16-1200_20260516_124636 \
  --policy.type=act \
  --output_dir=outputs/train/act-so101-test-may16-1200-local \
  --job_name=job-act-so101-test-may16-1200-local \
  --policy.device=mps \
  --wandb.enable=true \
  --policy.repo_id="${HF_USER}"/my_policy \
  --steps=100