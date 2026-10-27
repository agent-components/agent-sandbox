#!/bin/sh
# Build-time: install Google Chrome. Deb lands in /opt/google/chrome (FHS);
# persistence is /data at runtime, so Chrome can stay in /opt — no relocate.
set -eux

export DEBIAN_FRONTEND=noninteractive
sh /tmp/use-debian-mirror.sh
apt-get update
apt-get install -y --no-install-recommends \
  /mnt/vendor/google-chrome-stable_current_amd64.deb
google-chrome-stable --version

# --no-sandbox 是刚需。这样无论谁调用 google-chrome-stable / chrome-cdp，都会带上这些参数，不用每个启动脚本再写一遍。
rm -f /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable.real
printf '%s\n' '#!/bin/sh' 'exec /usr/bin/google-chrome-stable.real --no-sandbox --disable-gpu "$@"' \
  > /usr/bin/google-chrome-stable

chmod 755 /usr/bin/google-chrome-stable

test -x /usr/bin/google-chrome-stable

google-chrome-stable --version
