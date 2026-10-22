#!/bin/sh
# Build-time: install Node 24 under ~/.local/node-v24 + bin symlinks.
# npm cache / global prefix → /opt/npm（持久盘）；Node 本体仍在家目录。
# playwright-cli 不预装，用 npx @playwright/cli 执行。
set -eux

NODE_VER=v24.22.0
NODE_HOME=/home/sandbox/.local/node-v24
NODE_TAR="/mnt/vendor/node-${NODE_VER}-linux-x64.tar.xz"
NPM_OPT=/opt/npm

test -f "$NODE_TAR"
mkdir -p "$NODE_HOME" "$NODE_HOME/etc" "$NPM_OPT/cache"
tar -xJf "$NODE_TAR" -C "$NODE_HOME" --strip-components=1
ln -sf "$NODE_HOME/bin/node" /home/sandbox/.local/bin/node
ln -sf "$NODE_HOME/bin/npm" /home/sandbox/.local/bin/npm
ln -sf "$NODE_HOME/bin/npx" /home/sandbox/.local/bin/npx
export PATH="/home/sandbox/.local/bin:$PATH"

# 配置落在 Node 树（不被 /opt 挂载覆盖）；cache / 全局 node_modules 指向 /opt。
cat > "$NODE_HOME/etc/npmrc" <<EOF
cache=${NPM_OPT}/cache
prefix=${NPM_OPT}
EOF

node --version
npm --version
npx --version
