#!/bin/sh
# Build-time: install Node 24 under ~/.local/node-v24 + bin symlinks, then @playwright/cli.
set -eux

NODE_VER="${NODE_VER:-v24.22.0}"
NODE_TAR="/tmp/node-${NODE_VER}-linux-x64.tar.xz"

test -f "$NODE_TAR"
mkdir -p /home/sandbox/.local/node-v24
tar -xJf "$NODE_TAR" -C /home/sandbox/.local/node-v24 --strip-components=1
rm -f "$NODE_TAR"
ln -sf /home/sandbox/.local/node-v24/bin/node /home/sandbox/.local/bin/node
ln -sf /home/sandbox/.local/node-v24/bin/npm /home/sandbox/.local/bin/npm
ln -sf /home/sandbox/.local/node-v24/bin/npx /home/sandbox/.local/bin/npx
export PATH="/home/sandbox/.local/bin:$PATH"
npm i -g @playwright/cli
ln -sf /home/sandbox/.local/node-v24/bin/playwright-cli /home/sandbox/.local/bin/playwright-cli || true
test -x /home/sandbox/.local/bin/playwright-cli \
  || test -x /home/sandbox/.local/node-v24/bin/playwright-cli
node --version
npm --version
command -v playwright-cli || ls -la /home/sandbox/.local/node-v24/bin/
