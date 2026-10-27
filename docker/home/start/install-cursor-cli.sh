#!/usr/bin/env bash
# 把 Cursor CLI 装到 $CURSOR_PREFIX（默认 /data/cursor）。
# 官方安装脚本写死 ~/.local/share/cursor-agent，只能用软链拐到 /data；
# 配置/数据靠 CURSOR_CONFIG_DIR / CURSOR_DATA_DIR，不再链 ~/.cursor。
#
#   install-cursor-cli.sh
#   CURSOR_REINSTALL=1 install-cursor-cli.sh

set -euo pipefail

PREFIX="${CURSOR_PREFIX:-/data/cursor}"
SHARE="$PREFIX/share"
BIN_DIR="$PREFIX/bin"
CONFIG_DIR="${CURSOR_CONFIG_DIR:-$PREFIX/config}"
DATA_DIR="${CURSOR_DATA_DIR:-$PREFIX/data}"
ENV_FILE="$PREFIX/env.sh"

HOME_DIR="${HOME:-/root}"
LOCAL_AGENT="$HOME_DIR/.local/share/cursor-agent"
LOCAL_BIN="$HOME_DIR/.local/bin"

mkdir -p "$SHARE" "$BIN_DIR" "$CONFIG_DIR" "$DATA_DIR" \
  "$(dirname "$LOCAL_AGENT")" "$LOCAL_BIN"

# /data 已挂载；官方安装器只认此路径，直接链到卷上。
ln -sfn "$SHARE" "$LOCAL_AGENT"

export CURSOR_PREFIX="$PREFIX"
export CURSOR_CONFIG_DIR="$CONFIG_DIR"
export CURSOR_DATA_DIR="$DATA_DIR"
export PATH="$BIN_DIR:$PATH"

latest_agent() {
  local dir mtime latest latest_mtime
  latest=""
  latest_mtime=0
  [[ -d "$SHARE/versions" ]] || return 0
  for dir in "$SHARE/versions"/*; do
    [[ -d "$dir" && -f "$dir/cursor-agent" ]] || continue
    [[ "$(basename "$dir")" == .* ]] && continue
    mtime="$(stat -c %Y "$dir")"
    if (( mtime > latest_mtime )); then
      latest_mtime=$mtime
      latest="$dir/cursor-agent"
    fi
  done
  if [[ -n "$latest" ]]; then
    printf '%s\n' "$latest"
  fi
}

if [[ "${CURSOR_REINSTALL:-0}" == "1" ]] || [[ -z "$(latest_agent)" ]]; then
  curl https://cursor.com/install -fsS | bash
fi

AGENT_BIN="$(latest_agent)"
if [[ -z "$AGENT_BIN" ]]; then
  echo "安装结束，但没有找到 cursor-agent" >&2
  exit 1
fi

ln -sfn "$AGENT_BIN" "$BIN_DIR/agent"
ln -sfn "$BIN_DIR/agent" "$BIN_DIR/cursor-agent"
ln -sfn "$BIN_DIR/agent" "$LOCAL_BIN/agent"
ln -sfn "$BIN_DIR/cursor-agent" "$LOCAL_BIN/cursor-agent"

cat >"$ENV_FILE" <<EOF
export CURSOR_PREFIX="$PREFIX"
export CURSOR_CONFIG_DIR="$CONFIG_DIR"
export CURSOR_DATA_DIR="$DATA_DIR"
export PATH="$BIN_DIR:\$PATH"
EOF

for rc in "$HOME_DIR/.bashrc" "$HOME_DIR/.profile"; do
  if [[ -f "$rc" ]] && grep -qF "$ENV_FILE" "$rc"; then
    continue
  fi
  printf '\n. "%s"\n' "$ENV_FILE" >>"$rc"
done

# shellcheck disable=SC1090
. "$ENV_FILE"
echo "Cursor CLI: $("$BIN_DIR/agent" --version)"
echo "程序: $AGENT_BIN"
echo "配置: $CONFIG_DIR"
echo "数据: $DATA_DIR"
echo "环境: $ENV_FILE"
