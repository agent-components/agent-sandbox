#!/bin/sh
# Run as root from entrypoint before dropping to sandbox.
# Default program paths become symlinks; real files live under /opt.
# If a default path is already a real directory, move its contents into
# /opt first — ln alone does not migrate data.
set -eu

HOME_DIR=/home/sandbox

# Move an existing real directory into $target, then replace $source with a symlink.
link_to_opt() {
  source=$1
  target=$2

  mkdir -p "$target" "$(dirname "$source")"

  if [ -L "$source" ]; then
    ln -sfn "$target" "$source"
    return 0
  fi

  if [ -d "$source" ]; then
    find "$source" -mindepth 1 -maxdepth 1 -exec mv {} "$target/" \;
    rmdir "$source"
  elif [ -e "$source" ]; then
    echo "cannot link $source -> $target: path exists and is not a directory" >&2
    exit 1
  fi

  ln -sfn "$target" "$source"
}

mkdir -p \
  /opt/downloads \
  /opt/google-chrome-cdp \
  /opt/log \
  /opt/npm \
  /opt/playwright-cli/output \
  "$HOME_DIR/.local/state" \
  "$HOME_DIR/.cache" \
  "$HOME_DIR/.config"

link_to_opt "$HOME_DIR/Downloads" /opt/downloads
link_to_opt "$HOME_DIR/.config/google-chrome" /opt/google-chrome-cdp
link_to_opt "$HOME_DIR/.local/state/log" /opt/log
link_to_opt "$HOME_DIR/.npm" /opt/npm
link_to_opt "$HOME_DIR/.cache/ms-playwright" /opt/playwright-cli
link_to_opt "$HOME_DIR/.playwright-cli" /opt/playwright-cli/output

chown sandbox:sandbox /opt
chown -R sandbox:sandbox \
  /opt/downloads \
  /opt/google-chrome-cdp \
  /opt/log \
  /opt/npm \
  /opt/playwright-cli
chown -h sandbox:sandbox \
  "$HOME_DIR/Downloads" \
  "$HOME_DIR/.config/google-chrome" \
  "$HOME_DIR/.local/state/log" \
  "$HOME_DIR/.npm" \
  "$HOME_DIR/.cache/ms-playwright" \
  "$HOME_DIR/.playwright-cli"
