#!/bin/sh
# 第一步装官方 Node（tarball），再打 dummy 包占住 nodejs，避免后面 novnc 拉回 Debian Node。
# npm cache/prefix 由镜像 ENV 指到 /data；playwright-cli 不预装，用 npx @playwright/cli。
set -eux

NODE_VER=v24.22.0
NODE_HOME=/root/.local/node-v24
NODE_TAR="/mnt/vendor/node-${NODE_VER}-linux-x64.tar.xz"

export DEBIAN_FRONTEND=noninteractive
sh /tmp/use-debian-mirror.sh
apt-get update
# tar -xJf 需要 xz；slim 基座默认没有。
apt-get install -y --no-install-recommends xz-utils

test -f "$NODE_TAR"
mkdir -p "$NODE_HOME" /root/.local/bin
tar -xJf "$NODE_TAR" -C "$NODE_HOME" --strip-components=1

ln -sfn "$NODE_HOME/bin/node" /usr/bin/node
ln -sfn "$NODE_HOME/bin/npm" /usr/bin/npm
ln -sfn "$NODE_HOME/bin/npx" /usr/bin/npx
ln -sfn node /usr/bin/nodejs

ln -sfn "$NODE_HOME/bin/node" /root/.local/bin/node
ln -sfn "$NODE_HOME/bin/npm" /root/.local/bin/npm
ln -sfn "$NODE_HOME/bin/npx" /root/.local/bin/npx

# 占住 apt 的 nodejs 名字，后面装 novnc 时不会再拉 Debian nodejs。
DUMMY_DIR=$(mktemp -d)
mkdir -p "$DUMMY_DIR/DEBIAN"
cat > "$DUMMY_DIR/DEBIAN/control" <<CTRL
Package: nodejs
Version: 24.22.0-local1
Section: misc
Priority: optional
Architecture: all
Maintainer: agent-sandbox
Description: Dummy nodejs satisfying novnc; real binary is the official tarball.
CTRL
dpkg-deb --build "$DUMMY_DIR" /tmp/nodejs-dummy.deb
dpkg -i /tmp/nodejs-dummy.deb
rm -rf "$DUMMY_DIR" /tmp/nodejs-dummy.deb

export PATH="/root/.local/bin:$PATH"

test "$(node --version)" = "$NODE_VER"
test "$(/usr/bin/node --version)" = "$NODE_VER"
test "$(nodejs --version)" = "$NODE_VER"
npm --version
npx --version
