#!/bin/sh
# Build-time: install XFCE / VNC / noVNC / utils (Debian).
set -eux
export DEBIAN_FRONTEND=noninteractive

/tmp/use-debian-mirror.sh
apt-get update
apt-get install -y --no-install-recommends \
  xfce4 xfce4-terminal thunar \
  tigervnc-standalone-server \
  novnc websockify \
  python3 openssl \
  curl ca-certificates gnupg \
  dbus-x11 x11-utils \
  procps psmisc iproute2 \
  xz-utils \
  fonts-wqy-zenhei fonts-wqy-microhei fonts-dejavu-core \
  locales \
  scrot \
  xdotool \
  wmctrl \
  tzdata

dpkg -l fonts-wqy-zenhei tzdata >/dev/null
ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo Asia/Shanghai >/etc/timezone
printf 'LANG=C.UTF-8\n' >/etc/default/locale
