#!/bin/sh
# npm cache/prefix 由镜像 ENV 指到 /data；Node 本体在家目录。
# playwright-cli 不预装，用 npx @playwright/cli 执行。
set -eux

NODE_VER=v24.22.0
NODE_HOME=/root/.local/node-v24
NODE_TAR="/mnt/vendor/node-${NODE_VER}-linux-x64.tar.xz"

test -f "$NODE_TAR"
mkdir -p "$NODE_HOME"
tar -xJf "$NODE_TAR" -C "$NODE_HOME" --strip-components=1
ln -sf "$NODE_HOME/bin/node" /root/.local/bin/node
ln -sf "$NODE_HOME/bin/npm" /root/.local/bin/npm
ln -sf "$NODE_HOME/bin/npx" /root/.local/bin/npx
export PATH="/root/.local/bin:$PATH"

node --version
npm --version
npx --version
