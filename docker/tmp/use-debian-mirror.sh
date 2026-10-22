#!/bin/sh
# deb.debian.org times out from this network. trixie-slim has no CA bundle yet, so stay on HTTP.
set -eu
MIRROR=http://mirrors.ustc.edu.cn
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
  sed -i "s|http://deb.debian.org|${MIRROR}|g" /etc/apt/sources.list.d/debian.sources
fi
if [ -f /etc/apt/sources.list ]; then
  sed -i "s|http://deb.debian.org|${MIRROR}|g" /etc/apt/sources.list
fi
