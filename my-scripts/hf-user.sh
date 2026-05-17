#!/usr/bin/env bash

HF_USER=$(NO_COLOR=1 hf auth whoami | awk -F': *' '/user:/ {print $2}')
echo "$HF_USER"
