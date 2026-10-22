#!/usr/bin/env bash
# Prefetch google-chrome-stable .deb for Docker builds (apt to dl.google.com can flake in CN).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${ROOT}/docker/home/sandbox/packages"
DEB_NAME="google-chrome-stable_current_amd64.deb"
URL="https://dl.google.com/linux/direct/${DEB_NAME}"
OUT="${OUT_DIR}/${DEB_NAME}"

mkdir -p "${OUT_DIR}"
echo "Downloading ${URL}"
curl -fL --retry 3 --retry-delay 2 -o "${OUT}.partial" "${URL}"
mv -f "${OUT}.partial" "${OUT}"
ls -lh "${OUT}"
echo "Saved to ${OUT}"
