#!/bin/sh
# Build-time: install XFCE / VNC / noVNC / utils (Debian).
set -eux
export DEBIAN_FRONTEND=noninteractive

sh /tmp/use-debian-mirror.sh
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
  tzdata \
  openssh-server openssh-client \
  fcitx5 fcitx5-chinese-addons \
  fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 \
  xclip

dpkg -l fonts-wqy-zenhei tzdata fcitx5 fcitx5-chinese-addons xclip >/dev/null
ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo Asia/Shanghai >/etc/timezone
printf 'LANG=C.UTF-8\n' >/etc/default/locale
# Session uses zh_CN.UTF-8 (xstartup). Container default stays C.UTF-8.
if ! grep -qx 'zh_CN.UTF-8 UTF-8' /etc/locale.gen; then
  printf 'zh_CN.UTF-8 UTF-8\n' >> /etc/locale.gen
fi
locale-gen zh_CN.UTF-8
