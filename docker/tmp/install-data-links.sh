#!/bin/sh
# Run as root from entrypoint. Ensure /data dirs exist for an empty mount.
set -eu

mkdir -p \
  /data/google-chrome \
  /data/chrome-cache \
  /data/downloads \
  /data/npm \
  "$LOG_DIR"
