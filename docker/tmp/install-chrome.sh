#!/bin/sh
set -eux

export DEBIAN_FRONTEND=noninteractive
sh /tmp/use-debian-mirror.sh
apt-get update
apt-get install -y --no-install-recommends \
  /mnt/vendor/google-chrome-stable_current_amd64.deb
google-chrome-stable --version

# --no-sandbox 是刚需。这样无论谁调用 google-chrome-stable / chrome-cdp，都会带上这些参数，不用每个启动脚本再写一遍。
rm -f /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable.real
ln -sfn /opt/google/chrome/google-chrome /usr/bin/google-chrome-stable.real
printf '%s\n' '#!/bin/sh' 'exec /usr/bin/google-chrome-stable.real --no-sandbox --disable-gpu "$@"' \
  > /usr/bin/google-chrome-stable

chmod 755 /usr/bin/google-chrome-stable

test -x /opt/google/chrome/google-chrome
test -x /usr/bin/google-chrome-stable

google-chrome-stable --version
