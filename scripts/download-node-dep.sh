#!/usr/bin/env bash
# Prefetch Node.js linux-x64 tarball for Docker builds (same pattern as Chrome .deb).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE_VER="${NODE_VER:-v24.22.0}"
OUT_DIR="${ROOT}/vendor"
TAR_NAME="node-${NODE_VER}-linux-x64.tar.xz"
URL="https://npmmirror.com/mirrors/node/${NODE_VER}/${TAR_NAME}"
OUT="${OUT_DIR}/${TAR_NAME}"

mkdir -p "${OUT_DIR}"
echo "Downloading ${URL}"
curl -fL --retry 3 --retry-delay 2 -o "${OUT}.partial" "${URL}"
mv -f "${OUT}.partial" "${OUT}"
ls -lh "${OUT}"
echo "Saved to ${OUT}"
