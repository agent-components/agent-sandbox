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
#   AGENT_GATEWAY_HOME  解压缓存（默认 /data/agent-gateway）
#   AGENT_GATEWAY_BIN   安装目标（默认 /root/.local/bin/agent-gateway）
set -eu

SRC="${AGENT_GATEWAY_SRC:-/tmp/agent-gateway}"
BIN_DIR="$(dirname "${AGENT_GATEWAY_BIN:-/root/.local/bin/agent-gateway}")"
BIN="${AGENT_GATEWAY_BIN:-$BIN_DIR/agent-gateway}"
CACHE_HOME="${AGENT_GATEWAY_HOME:-/data/agent-gateway}"
LOG_ROOT="${LOG_DIR:-/data/log}"
LOG_DIR="$LOG_ROOT/agent-gateway"
PID_FILE="${AGENT_GATEWAY_PID_FILE:-$HOME/.config/agent-gateway.pid}"
PORT="${PORT:-6090}"
HOST="${HOST:-0.0.0.0}"
CWD="${AGENT_GATEWAY_CWD:-/home/workspace}"
MODE="${1:-install}"

need_src() {
  if [ ! -f "$SRC" ]; then
    echo "找不到 agent-gateway 二进制: $SRC" >&2
    exit 1
  fi
}

install_bin() {
  need_src
  mkdir -p "$BIN_DIR" "$CACHE_HOME" "$LOG_DIR" "$(dirname "$PID_FILE")"
  chmod +x "$SRC"
  # 装到 PATH；源文件仍留在 /tmp（镜像层），运行时走 BIN。
  cp -f "$SRC" "$BIN"
  chmod +x "$BIN"
}

is_running() {
  if [ -f "$PID_FILE" ]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  # 兜底：按监听端口判断
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
      # 给一点时间退出；顽固则强杀
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
  if is_running; then
    echo "agent-gateway 已在运行 (port $PORT)"
    return 0
  fi

  if ! command -v node >/dev/null 2>&1; then
    echo "需要 Node ≥ 22.13（当前 PATH 找不到 node）" >&2
    exit 1
  fi

  if [ -z "${CURSOR_API_KEY:-}" ]; then
    echo "警告: 未设置 CURSOR_API_KEY，Cursor provider 将不可用" >&2
  fi

  mkdir -p "$LOG_DIR" "$(dirname "$PID_FILE")" "$CACHE_HOME" "$CWD"

  # 自解压产物与静态 UI 落在 AGENT_GATEWAY_HOME
  export AGENT_GATEWAY_HOME="$CACHE_HOME"
  export AGENT_GATEWAY_CWD="$CWD"
  export PORT HOST
  # CURSOR_API_KEY / AGENT_GATEWAY_TOKEN / QWEN_API_KEY：若调用方已 export，原样继承

  nohup "$BIN" >"$LOG_DIR/agent-gateway.log" 2>&1 &
  echo $! >"$PID_FILE"

  echo "agent-gateway 已启动"
  echo "  pid:  $(cat "$PID_FILE")"
  echo "  url:  http://${HOST}:${PORT}"
  echo "  log:  $LOG_DIR/agent-gateway.log"
  echo "  bin:  $BIN"
  echo "  home: $CACHE_HOME"
  if [ -z "${AGENT_GATEWAY_TOKEN:-}" ]; then
    echo "  token 未预设，请看启动日志里自动生成的 AGENT_GATEWAY_TOKEN"
  fi
}

case "$MODE" in
  install)
    install_bin
    echo "agent-gateway 已安装: $BIN"
    ;;
  start|"")
    if [ ! -x "$BIN" ]; then
      install_bin
    fi
    start_gateway
    ;;
  ensure)
    if [ ! -x "$BIN" ]; then
      # 未装过则安静跳过
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
