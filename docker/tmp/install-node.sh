#!/bin/sh
# Build-time: install Node 24 under ~/.local/node-v24 + bin symlinks.
# npm 使用默认 cache（~/.npm）。该路径由镜像链到 /opt/npm，Node 本体仍在家目录。
# playwright-cli 不预装，用 npx @playwright/cli 执行。
set -eux

NODE_VER=v24.22.0
NODE_HOME=/home/sandbox/.local/node-v24
NODE_TAR="/mnt/vendor/node-${NODE_VER}-linux-x64.tar.xz"

test -f "$NODE_TAR"
mkdir -p "$NODE_HOME"
tar -xJf "$NODE_TAR" -C "$NODE_HOME" --strip-components=1
ln -sf "$NODE_HOME/bin/node" /home/sandbox/.local/bin/node
ln -sf "$NODE_HOME/bin/npm" /home/sandbox/.local/bin/npm
ln -sf "$NODE_HOME/bin/npx" /home/sandbox/.local/bin/npx
export PATH="/home/sandbox/.local/bin:$PATH"

node --version
npm --version
npx --version
