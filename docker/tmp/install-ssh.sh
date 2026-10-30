#!/bin/sh
# OpenSSH：构建时写好 sshd 配置；运行时准备密钥/密码并启动，供外部 IDE Remote SSH。
#
#   sh /tmp/install-ssh.sh install   # 仅配置（镜像构建用）
#   sh /tmp/install-ssh.sh start     # 准备认证 + 启动 sshd（入口用）
#   sh /tmp/install-ssh.sh stop
#
# 认证（至少一种，否则无法登录）：
#   SSH_PASSWORD          设置 root 密码并启用密码登录
#   SSH_AUTHORIZED_KEYS   写入 /root/.ssh/authorized_keys（可多行）
#   /data/ssh/authorized_keys  持久化公钥（卷挂载后自动生效）
#
# 其它：
#   SSH_PORT              容器内监听端口，默认 22
#   /data/ssh/host_*      主机密钥持久化（换容器后 IDE 不反复告警）
set -eu

MODE="${1:-install}"
SSH_PORT="${SSH_PORT:-22}"
DATA_SSH="${SSH_DATA_DIR:-/data/ssh}"
LOG_ROOT="${LOG_DIR:-/data/log}"
LOG_DIR="$LOG_ROOT/ssh"
PID_FILE="${SSH_PID_FILE:-/run/sshd.pid}"
DROP_IN="/etc/ssh/sshd_config.d/agent-sandbox.conf"

install_ssh() {
  if ! command -v sshd >/dev/null 2>&1; then
    echo "openssh-server 未安装" >&2
    exit 1
  fi

  mkdir -p /run/sshd /etc/ssh/sshd_config.d /root/.ssh
  chmod 700 /root/.ssh

  # 容器友好：允许 root、转发（IDE 端口转发）、保活；主机密钥改由 /data 提供。
  cat >"$DROP_IN" <<'EOF'
Port 22
ListenAddress 0.0.0.0
Protocol 2
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
X11Forwarding no
AllowTcpForwarding yes
GatewayPorts no
ClientAliveInterval 30
ClientAliveCountMax 6
PrintMotd no
Subsystem sftp /usr/lib/openssh/sftp-server
AuthorizedKeysFile .ssh/authorized_keys /data/ssh/authorized_keys
HostKey /data/ssh/ssh_host_ed25519_key
HostKey /data/ssh/ssh_host_rsa_key
EOF

  # 构建期生成一份兜底 host key（无 /data 卷时也能起）；运行时优先用 /data/ssh。
  if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -A
  fi

  echo "sshd 已配置: $DROP_IN"
}

ensure_host_keys() {
  mkdir -p "$DATA_SSH"
  chmod 700 "$DATA_SSH"

  if [ ! -f "$DATA_SSH/ssh_host_ed25519_key" ]; then
    if [ -f /etc/ssh/ssh_host_ed25519_key ]; then
      cp -a /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key.pub "$DATA_SSH/" 2>/dev/null || true
    fi
    if [ ! -f "$DATA_SSH/ssh_host_ed25519_key" ]; then
      ssh-keygen -t ed25519 -f "$DATA_SSH/ssh_host_ed25519_key" -N "" -q
    fi
  fi

  if [ ! -f "$DATA_SSH/ssh_host_rsa_key" ]; then
    if [ -f /etc/ssh/ssh_host_rsa_key ]; then
      cp -a /etc/ssh/ssh_host_rsa_key /etc/ssh/ssh_host_rsa_key.pub "$DATA_SSH/" 2>/dev/null || true
    fi
    if [ ! -f "$DATA_SSH/ssh_host_rsa_key" ]; then
      ssh-keygen -t rsa -b 3072 -f "$DATA_SSH/ssh_host_rsa_key" -N "" -q
    fi
  fi

  chmod 600 "$DATA_SSH"/ssh_host_*_key
  chmod 644 "$DATA_SSH"/ssh_host_*.pub 2>/dev/null || true
}

prepare_auth() {
  mkdir -p /root/.ssh "$DATA_SSH"
  chmod 700 /root/.ssh "$DATA_SSH"

  if [ -n "${SSH_AUTHORIZED_KEYS:-}" ]; then
    printf '%s\n' "$SSH_AUTHORIZED_KEYS" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
  fi

  # 卷上的公钥：若存在且家目录没有，则软链；两边都有则保留家目录（环境变量优先）
  if [ -f "$DATA_SSH/authorized_keys" ]; then
    chmod 600 "$DATA_SSH/authorized_keys" || true
    if [ ! -f /root/.ssh/authorized_keys ]; then
      ln -sfn "$DATA_SSH/authorized_keys" /root/.ssh/authorized_keys
    fi
  fi

  # 按需开关密码登录（写进 drop-in，避免改主配置）
  if [ -n "${SSH_PASSWORD:-}" ]; then
    echo "root:${SSH_PASSWORD}" | chpasswd
    sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' "$DROP_IN"
  else
    sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' "$DROP_IN"
  fi

  # 运行时端口
  sed -i "s/^Port .*/Port ${SSH_PORT}/" "$DROP_IN"

  has_keys=0
  if [ -f /root/.ssh/authorized_keys ] && [ -s /root/.ssh/authorized_keys ]; then
    has_keys=1
  fi
  if [ -f "$DATA_SSH/authorized_keys" ] && [ -s "$DATA_SSH/authorized_keys" ]; then
    has_keys=1
  fi

  if [ "$has_keys" -eq 0 ] && [ -z "${SSH_PASSWORD:-}" ]; then
    echo "警告: 未配置 SSH_PASSWORD / SSH_AUTHORIZED_KEYS /data/ssh/authorized_keys，sshd 会启动但无法登录" >&2
  fi
}

is_running() {
  if [ -f "$PID_FILE" ]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "sport = :${SSH_PORT}" 2>/dev/null | grep -q LISTEN
    return $?
  fi
  return 1
}

stop_sshd() {
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
    pids="$(ss -ltnp "sport = :${SSH_PORT}" 2>/dev/null | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u)"
    for pid in $pids; do
      kill "$pid" 2>/dev/null || true
    done
  fi
}

start_sshd() {
  if [ ! -f "$DROP_IN" ]; then
    install_ssh
  fi

  mkdir -p /run/sshd "$LOG_DIR" "$DATA_SSH"
  ensure_host_keys
  prepare_auth

  if is_running; then
    echo "sshd 已在运行 (port $SSH_PORT)"
    return 0
  fi

  # -D 前台；用 nohup 挂到入口进程树外，日志落盘
  nohup /usr/sbin/sshd -D -e >"$LOG_DIR/sshd.log" 2>&1 &
  echo $! >"$PID_FILE"

  echo "sshd 已启动"
  echo "  pid:  $(cat "$PID_FILE")"
  echo "  port: $SSH_PORT"
  echo "  user: root"
  echo "  cwd:  /home/workspace（IDE 可打开此目录）"
  echo "  log:  $LOG_DIR/sshd.log"
  echo "  keys: $DATA_SSH"
}

case "$MODE" in
  install)
    install_ssh
    ;;
  start|"")
    start_sshd
    ;;
  stop)
    stop_sshd
    echo "sshd 已停止"
    ;;
  *)
    echo "用法: $0 [install|start|stop]" >&2
    exit 2
    ;;
esac
