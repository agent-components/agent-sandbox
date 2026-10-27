#!/bin/sh
# npm cache/prefix 由镜像 ENV 指到 /data；Node 本体在家目录。
# playwright-cli 不预装，用 npx @playwright/cli 执行。
# Debian nodejs（novnc 依赖拉进来的 v20）卸掉，改用官方 tarball，并接到 /usr/bin。
set -eux

NODE_VER=v24.22.0
NODE_HOME=/root/.local/node-v24
NODE_TAR="/mnt/vendor/node-${NODE_VER}-linux-x64.tar.xz"

test -f "$NODE_TAR"
mkdir -p "$NODE_HOME" /root/.local/bin
tar -xJf "$NODE_TAR" -C "$NODE_HOME" --strip-components=1

# novnc Depends: nodejs；用 force-depends 只卸 Debian Node，保留 novnc。
pkgs=$(dpkg-query -W -f='${Package}\n' nodejs 'libnode*' 'node-*' 2>/dev/null || true)
if [ -n "$pkgs" ]; then
  # shellcheck disable=SC2086
  dpkg --remove --force-depends $pkgs
fi

ln -sfn "$NODE_HOME/bin/node" /usr/bin/node
ln -sfn "$NODE_HOME/bin/npm" /usr/bin/npm
ln -sfn "$NODE_HOME/bin/npx" /usr/bin/npx
ln -sfn node /usr/bin/nodejs

ln -sfn "$NODE_HOME/bin/node" /root/.local/bin/node
ln -sfn "$NODE_HOME/bin/npm" /root/.local/bin/npm
ln -sfn "$NODE_HOME/bin/npx" /root/.local/bin/npx

export PATH="/root/.local/bin:$PATH"

test "$(node --version)" = "$NODE_VER"
test "$(/usr/bin/node --version)" = "$NODE_VER"
npm --version
npx --version
