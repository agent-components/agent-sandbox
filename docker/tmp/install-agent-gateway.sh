#!/bin/sh
# 把 /tmp/agent-gateway 一键二进制装到 PATH；可选后台启动 HTTP 网关（默认 :6090）。
#
#   sh /tmp/install-agent-gateway.sh install   # 仅安装（镜像构建用）
#   sh /tmp/install-agent-gateway.sh start     # 启动（缺 bin 则先装）；入口用
#   sh /tmp/install-agent-gateway.sh ensure    # 已装才启动；未装则跳过
#   sh /tmp/install-agent-gateway.sh stop      # 停止
#
# 环境变量（可选）：
#   CURSOR_API_KEY / AGENT_GATEWAY_TOKEN / PORT / HOST / AGENT_GATEWAY_CWD
#   AGENT_GATEWAY_HOME  解压缓存根目录（默认 /data/agent-gateway）
#                       实际解压到 $AGENT_GATEWAY_HOME/<version>
#   AGENT_GATEWAY_BIN   安装目标（默认 /root/.local/bin/agent-gateway）
#
# 官方启动器只在目标目录没有 dist/main.js 时解压。若把 AGENT_GATEWAY_HOME
# 指到固定目录，升级二进制后旧缓存会被继续使用。这里读取启动器头部的
# VERSION，版本不一致时先停进程、删掉其它版本和无版本旧目录，再解压新版本。
set -eu

SRC="${AGENT_GATEWAY_SRC:-/tmp/agent-gateway}"
BIN_DIR="$(dirname "${AGENT_GATEWAY_BIN:-/root/.local/bin/agent-gateway}")"
BIN="${AGENT_GATEWAY_BIN:-$BIN_DIR/agent-gateway}"
CACHE_HOME="${AGENT_GATEWAY_HOME:-/data/agent-gateway}"
STAMP="$CACHE_HOME/.current-version"
LOG_ROOT="${LOG_DIR:-/data/log}"
LOG_DIR="$LOG_ROOT/agent-gateway"
PID_FILE="${AGENT_GATEWAY_PID_FILE:-$HOME/.config/agent-gateway.pid}"
PORT="${PORT:-6090}"
HOST="${HOST:-0.0.0.0}"
CWD="${AGENT_GATEWAY_CWD:-/home/workspace}"
MODE="${1:-install}"
DESIRED_VERSION=""
RUNTIME_HOME=""

need_src() {
  if [ ! -f "$SRC" ]; then
    echo "找不到 agent-gateway 二进制: $SRC" >&2
    exit 1
  fi
}

# 启动器前几行有 VERSION="x.y.z"。只读头部，避免扫到后面的 tar。
launcher_version() {
  _file="$1"
  if [ ! -f "$_file" ]; then
    return 1
  fi
  _ver="$(head -n 8 "$_file" | sed -n 's/^VERSION="\(.*\)".*/\1/p' | head -n 1)"
  if [ -z "$_ver" ]; then
    return 1
  fi
  printf '%s\n' "$_ver"
}

install_bin() {
  need_src
  # 只装二进制。/data 常被卷盖住，缓存和日志目录留给 start（挂载之后）再建。
  mkdir -p "$BIN_DIR"
  chmod +x "$SRC"
  # 装到 PATH；源文件仍留在 /tmp（镜像层），运行时走 BIN。
  cp -f "$SRC" "$BIN"
  chmod +x "$BIN"
}

# 源二进制版本变了就覆盖已安装副本。容器换镜像时两者通常一致；
# 只替换 /tmp/agent-gateway 再 start 时，这里会把新版本装上。
sync_bin() {
  if [ ! -f "$SRC" ]; then
    if [ ! -x "$BIN" ]; then
      echo "找不到 agent-gateway 二进制: $SRC" >&2
      exit 1
    fi
    return 0
  fi
  src_ver="$(launcher_version "$SRC")" || {
    echo "无法读取 agent-gateway 版本: $SRC" >&2
    exit 1
  }
  bin_ver=""
  if [ -x "$BIN" ]; then
    bin_ver="$(launcher_version "$BIN" || true)"
  fi
  if [ -x "$BIN" ] && [ "$src_ver" = "$bin_ver" ]; then
    return 0
  fi
  if is_running; then
    echo "agent-gateway ${bin_ver:-无} -> ${src_ver}，先停止再更新二进制"
    stop_gateway
  fi
  install_bin
  echo "agent-gateway 已安装 $src_ver: $BIN"
}

# 把运行目录指到 $CACHE_HOME/<version>，并删掉对不上的解压结果。
refresh_cache() {
  ver="$(launcher_version "$BIN")" || {
    echo "无法读取已安装 agent-gateway 的版本: $BIN" >&2
    exit 1
  }
  stamp=""
  if [ -f "$STAMP" ]; then
    stamp="$(tr -d '[:space:]' <"$STAMP" || true)"
  fi
  runtime="$CACHE_HOME/$ver"
  legacy=0
  if [ -e "$CACHE_HOME/dist" ] || [ -e "$CACHE_HOME/node_modules" ] || [ -e "$CACHE_HOME/package.json" ] || [ -e "$CACHE_HOME/.payload.tgz" ]; then
    legacy=1
  fi

  if is_running && { [ "$stamp" != "$ver" ] || [ "$legacy" -eq 1 ]; }; then
    echo "agent-gateway 缓存 ${stamp:-旧布局} 与版本 $ver 不一致，重启以更新"
    stop_gateway
  fi

  if [ "$legacy" -eq 1 ]; then
    echo "清理无版本号的 agent-gateway 缓存: $CACHE_HOME"
    rm -rf "$CACHE_HOME/dist" "$CACHE_HOME/node_modules" "$CACHE_HOME/package.json" "$CACHE_HOME/.payload.tgz"
  fi

  if [ -d "$CACHE_HOME" ]; then
    for dir in "$CACHE_HOME"/*; do
      [ -d "$dir" ] || continue
      name="$(basename "$dir")"
      if [ "$name" != "$ver" ]; then
        echo "移除过期 agent-gateway 缓存 $name"
        rm -rf "$dir"
      fi
    done
  fi

  mkdir -p "$runtime"
  DESIRED_VERSION="$ver"
  RUNTIME_HOME="$runtime"
  # 启动器把 AGENT_GATEWAY_HOME 当作解压目录本身，不会再拼版本号。
  export AGENT_GATEWAY_HOME="$runtime"
}

is_running() {
  if [ -f "$PID_FILE" ]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "sport = :${PORT}" 2>/dev/null | grep -q LISTEN
    return $?
  fi
  return 1
}

stop_gateway() {
  if [ -f "$PID_FILE" ]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "${pid:-}" ]; then
      kill "$pid" 2>/dev/null || true
      i=0
      while [ "$i" -lt 20 ] && kill -0 "$pid" 2>/dev/null; do
        i=$((i + 1))
        sleep 0.1
      done
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
  fi
  if command -v ss >/dev/null 2>&1; then
    pids="$(ss -ltnp "sport = :${PORT}" 2>/dev/null | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u)"
    for pid in $pids; do
      kill "$pid" 2>/dev/null || true
    done
  fi
}

start_gateway() {
  sync_bin
  refresh_cache

  if is_running; then
    echo "agent-gateway 已在运行 (port $PORT, version $DESIRED_VERSION)"
    return 0
  fi

  if ! command -v node >/dev/null 2>&1; then
    echo "需要 Node ≥ 22.13（当前 PATH 找不到 node）" >&2
    exit 1
  fi

  if [ -z "${CURSOR_API_KEY:-}" ]; then
    echo "警告: 未设置 CURSOR_API_KEY，Cursor provider 将不可用" >&2
  fi

  mkdir -p "$LOG_DIR" "$(dirname "$PID_FILE")" "$RUNTIME_HOME" "$CWD"

  # 官方启动器：解压到 AGENT_GATEWAY_HOME/<version>，再 node dist/main.js
  export AGENT_GATEWAY_CWD="$CWD"
  export PORT HOST

  : >"$LOG_DIR/agent-gateway.log"
  nohup "$BIN" >"$LOG_DIR/agent-gateway.log" 2>&1 &
  echo $! >"$PID_FILE"

  sleep 1
  if ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "agent-gateway 启动失败，日志：" >&2
    tail -50 "$LOG_DIR/agent-gateway.log" >&2 || true
    rm -f "$PID_FILE"
    exit 1
  fi

  printf '%s\n' "$DESIRED_VERSION" >"$STAMP"

  echo "agent-gateway 已启动"
  echo "  pid:     $(cat "$PID_FILE")"
  echo "  version: $DESIRED_VERSION"
  echo "  url:     http://${HOST}:${PORT}"
  echo "  log:     $LOG_DIR/agent-gateway.log"
  echo "  bin:     $BIN"
  echo "  home:    $RUNTIME_HOME"
  if [ -z "${AGENT_GATEWAY_TOKEN:-}" ]; then
    echo "  token 未预设，请看启动日志里自动生成的 AGENT_GATEWAY_TOKEN"
  fi
}

case "$MODE" in
  install)
    install_bin
    echo "agent-gateway 已安装: $BIN ($(launcher_version "$BIN"))"
    ;;
  start|"")
    if [ ! -x "$BIN" ]; then
      install_bin
    fi
    start_gateway
    ;;
  ensure)
    if [ ! -x "$BIN" ]; then
      exit 0
    fi
    start_gateway
    ;;
  stop)
    stop_gateway
    echo "agent-gateway 已停止"
    ;;
  *)
    echo "用法: $0 [install|start|ensure|stop]" >&2
    exit 2
    ;;
esac
