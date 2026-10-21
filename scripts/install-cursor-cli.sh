#!/usr/bin/env bash
# 把 Cursor CLI 装到 /opt/cursor。家目录只保留软链接。
# 家目录不在持久盘上时，重启后再执行本脚本会把链接补回去；已有版本不会重新下载。
#
#   install-cursor-cli.sh              安装或补链接
#   CURSOR_REINSTALL=1 install-cursor-cli.sh

set -euo pipefail

PREFIX=/opt/cursor
SHARE="$PREFIX/share"
BIN_DIR="$PREFIX/bin"
CONFIG_DIR="$PREFIX/config"
DATA_DIR="$PREFIX/data"
DOT_CURSOR="$PREFIX/dot-cursor"
ENV_FILE="$PREFIX/env.sh"

HOME_DIR="${HOME:-/home/sandbox}"
LOCAL_SHARE="$HOME_DIR/.local/share"
LOCAL_AGENT="$LOCAL_SHARE/cursor-agent"
LOCAL_BIN="$HOME_DIR/.local/bin"
HOME_CURSOR="$HOME_DIR/.cursor"

mkdir -p "$SHARE" "$BIN_DIR" "$CONFIG_DIR" "$DATA_DIR" "$DOT_CURSOR" "$LOCAL_SHARE" "$LOCAL_BIN"

# 家目录里如果已经有一份真目录，先挪到 /opt，再换成软链接。
move_into_prefix() {
  local source="$1"
  local target="$2"
  if [[ -L "$source" || ! -e "$source" ]]; then
    return 0
  fi
  if [[ -d "$source" ]]; then
    shopt -s dotglob nullglob
    local entry
    for entry in "$source"/*; do
      mv "$entry" "$target/"
    done
    shopt -u dotglob nullglob
    rmdir "$source"
    return 0
  fi
  echo "无法迁移，路径已存在且不是目录: $source" >&2
  exit 1
}

move_into_prefix "$LOCAL_AGENT" "$SHARE"
move_into_prefix "$HOME_CURSOR" "$DOT_CURSOR"
ln -sfn "$SHARE" "$LOCAL_AGENT"
ln -sfn "$DOT_CURSOR" "$HOME_CURSOR"

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
ln -sfn "$BIN_DIR/agent" /usr/local/bin/agent
ln -sfn "$BIN_DIR/cursor-agent" /usr/local/bin/cursor-agent

cat >"$ENV_FILE" <<EOF
export PATH="$BIN_DIR:\$PATH"
export CURSOR_CONFIG_DIR="$CONFIG_DIR"
export CURSOR_DATA_DIR="$DATA_DIR"
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
