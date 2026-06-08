#!/usr/bin/env python

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = REPO_ROOT / "src"
if SRC_DIR.exists():
    sys.path.insert(0, str(SRC_DIR))

from lerobot.scripts.lerobot_check_sts3215 import main


if __name__ == "__main__":
    sys.exit(main())
