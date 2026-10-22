#!/bin/sh
# deb.debian.org times out from this network. trixie-slim has no CA bundle yet, so stay on HTTP.
# Drop docker-clean so BuildKit apt cache mounts can keep archives across builds.
set -eu
MIRROR=http://mirrors.ustc.edu.cn
rm -f /etc/apt/apt.conf.d/docker-clean
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
  sed -i "s|http://deb.debian.org|${MIRROR}|g" /etc/apt/sources.list.d/debian.sources
fi
if [ -f /etc/apt/sources.list ]; then
  sed -i "s|http://deb.debian.org|${MIRROR}|g" /etc/apt/sources.list
fi
