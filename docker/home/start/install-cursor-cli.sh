#!/usr/bin/env bash
# 可选：把 Cursor CLI 装到 $CURSOR_PREFIX（默认 /data/cursor）。
# 未装用户不受影响。装过后程序留在 /data；家目录软链会丢，由 entrypoint
# 发现 /data/.../env.sh 后调用 ensure 重建，不必每次重新下载。
#
#   install-cursor-cli.sh              # 首次安装；已装则只恢复链接
#   install-cursor-cli.sh ensure       # 仅恢复；未装则跳过（开机用）
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
MODE="${1:-install}"

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

# 重建开机后丢失的家目录软链、/data 上的 bin 别名，以及 shell 环境。
ensure_links() {
  local agent_bin="$1"

  mkdir -p "$SHARE" "$BIN_DIR" "$CONFIG_DIR" "$DATA_DIR" \
    "$(dirname "$LOCAL_AGENT")" "$LOCAL_BIN"

  # 官方安装器只认此路径；指向持久化的 /data。
  ln -sfn "$SHARE" "$LOCAL_AGENT"

  ln -sfn "$agent_bin" "$BIN_DIR/agent"
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

  export CURSOR_PREFIX="$PREFIX"
  export CURSOR_CONFIG_DIR="$CONFIG_DIR"
  export CURSOR_DATA_DIR="$DATA_DIR"
  export PATH="$BIN_DIR:$PATH"
}

AGENT_BIN="$(latest_agent)"

if [[ "$MODE" == "ensure" ]]; then
  if [[ -z "$AGENT_BIN" ]]; then
    exit 0
  fi
  ensure_links "$AGENT_BIN"
  exit 0
fi

mkdir -p "$SHARE" "$BIN_DIR" "$CONFIG_DIR" "$DATA_DIR" \
  "$(dirname "$LOCAL_AGENT")" "$LOCAL_BIN"
ln -sfn "$SHARE" "$LOCAL_AGENT"

export CURSOR_PREFIX="$PREFIX"
export CURSOR_CONFIG_DIR="$CONFIG_DIR"
export CURSOR_DATA_DIR="$DATA_DIR"
export PATH="$BIN_DIR:$PATH"

if [[ "${CURSOR_REINSTALL:-0}" == "1" ]] || [[ -z "$AGENT_BIN" ]]; then
  curl https://cursor.com/install -fsS | bash
  AGENT_BIN="$(latest_agent)"
fi

if [[ -z "$AGENT_BIN" ]]; then
  echo "安装结束，但没有找到 cursor-agent" >&2
  exit 1
fi

ensure_links "$AGENT_BIN"

echo "Cursor CLI: $("$BIN_DIR/agent" --version)"
echo "程序: $AGENT_BIN"
echo "配置: $CONFIG_DIR"
echo "数据: $DATA_DIR"
echo "环境: $ENV_FILE"
