#!/bin/sh
# Build-time: install google-chrome-stable (amd64) and relocate under /usr/local/google/chrome.
set -eux

if [ "${TARGETARCH:-}" != "amd64" ]; then
  echo "This image expects TARGETARCH=amd64 (google-chrome-stable). Rebuild with --platform linux/amd64." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
/tmp/use-debian-mirror.sh
apt-get update
apt-get install -y --no-install-recommends \
  /mnt/vendor/google-chrome-stable_current_amd64.deb
google-chrome-stable --version

mkdir -p /usr/local/google
mv /opt/google/chrome /usr/local/google/chrome
rmdir /opt/google 2>/dev/null || true
rm -f /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable.real
ln -sfn /usr/local/google/chrome/google-chrome /usr/bin/google-chrome-stable.real
printf '%s\n' '#!/bin/sh' 'exec /usr/bin/google-chrome-stable.real --no-sandbox --disable-gpu "$@"' \
  > /usr/bin/google-chrome-stable
chmod 755 /usr/bin/google-chrome-stable
test -x /usr/local/google/chrome/google-chrome
test -x /usr/bin/google-chrome-stable
google-chrome-stable --version
