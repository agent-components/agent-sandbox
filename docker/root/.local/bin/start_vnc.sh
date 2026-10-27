#!/bin/bash
# Start the virtual desktop only: VNC :1, noVNC :6080, dock keep-below.
# Desktop XFCE/dock config is baked by Dockerfile COPY — no runtime seed copy.
# Called by entrypoint.sh — do not put Chrome CDP logic here.
set -euo pipefail

export HOME="${HOME:-/root}"
export PATH="$HOME/.local/bin:$PATH"
export DISPLAY="${DISPLAY:-:1}"
export SANDBOX_DISPLAY_WIDTH="${SANDBOX_DISPLAY_WIDTH:-1920}"
export SANDBOX_DISPLAY_HEIGHT="${SANDBOX_DISPLAY_HEIGHT:-1080}"

display_ready() {
    DISPLAY=:1 xdpyinfo >/dev/null 2>&1
}

stop_port() {
    local port="$1"
    local pids pid
    pids=$(ss -ltnp "sport = :${port}" 2>/dev/null | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u)
    for pid in $pids; do
        kill "$pid" 2>/dev/null || true
    done
}

prepare_novnc_web() {
    local web_root="$HOME/.vnc/novnc-web"
    local item
    local custom_lite="$HOME/.local/share/novnc/vnc_lite.html"
    rm -rf "$web_root"
    mkdir -p "$web_root"
    for item in /usr/share/novnc/*; do
        ln -s "$item" "$web_root/$(basename "$item")"
    done
    rm -f "$web_root/vnc_lite.html"
    if [ -f "$custom_lite" ]; then
        cp "$custom_lite" "$web_root/vnc_lite.html"
    elif [ -f /usr/share/novnc/vnc_lite.html ]; then
        cp /usr/share/novnc/vnc_lite.html "$web_root/vnc_lite.html"
        sed -i 's|#top_bar {|#top_bar { display: none !important;|' \
            "$web_root/vnc_lite.html"
    fi
    # Package index.html redirects to vnc.html. Desktop is opened via vnc_lite.html directly.
    rm -f "$web_root/index.html"
}

ensure_tls_cert() {
    local cert="$HOME/.vnc/self.crt"
    local key="$HOME/.vnc/self.key"
    if [ -s "$cert" ] && [ -s "$key" ]; then
        return 0
    fi
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "$key" -out "$cert" -days 3650 \
        -subj "/CN=localhost" >/dev/null 2>&1
    chmod 600 "$key" "$cert"
}

start_websockify() {
    local port="$1"
    local token_file="$2"
    stop_port "$port"
    mkdir -p "$HOME/.local/state/log/novnc"
    nohup websockify --web="$HOME/.vnc/novnc-web" \
        --cert="$HOME/.vnc/self.crt" --key="$HOME/.vnc/self.key" \
        --token-plugin TokenFile --token-source "$token_file" \
        --heartbeat=30 \
        "0.0.0.0:${port}" \
        > "$HOME/.local/state/log/novnc/novnc-${port}.log" 2>&1 &
    echo $! > "$HOME/.vnc/novnc-${port}.pid"
}

start_panel_keep_below() {
    if [ ! -x "$HOME/.local/bin/panel-keep-below.sh" ]; then
        return 0
    fi
    if [ -f "$HOME/.config/panel-keep-below.pid" ]; then
        old=$(tr -d "[:space:]" < "$HOME/.config/panel-keep-below.pid" || true)
        if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
            kill "$old" 2>/dev/null || true
        fi
    fi
    mkdir -p "$HOME/.local/state/log/panel"
    DISPLAY=:1 nohup "$HOME/.local/bin/panel-keep-below.sh" \
        > "$HOME/.local/state/log/panel/panel-keep-below.log" 2>&1 &
    echo $! > "$HOME/.config/panel-keep-below.pid"
    DISPLAY=:1 "$HOME/.local/bin/panel-keep-below.sh" --once >/dev/null 2>&1 || true
}

main() {
    if [ -z "${NOVNC_TOKEN:-}" ]; then
        echo "NOVNC_TOKEN is required" >&2
        exit 1
    fi

    mkdir -p "$HOME/.vnc" "$HOME/.config"

    if ! display_ready; then
        vncserver -kill :1 >/dev/null 2>&1 || true
        local lock_pid=""
        if [ -f /tmp/.X1-lock ]; then
            lock_pid=$(tr -d '[:space:]' < /tmp/.X1-lock || true)
        fi
        if [ -z "$lock_pid" ] || ! kill -0 "$lock_pid" 2>/dev/null; then
            rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
            rm -f "$HOME/.vnc/"*:1.pid
            rm -f "$HOME/.config/tigervnc/"*:1.pid
        fi
        vncserver :1 -localhost yes \
            -geometry "${SANDBOX_DISPLAY_WIDTH}x${SANDBOX_DISPLAY_HEIGHT}" -depth 24 \
            -SecurityTypes None -desktop Desktop
    fi

    local token_file="$HOME/.vnc/novnc-targets"
    printf '%s: 127.0.0.1:5901\n' "$NOVNC_TOKEN" > "$token_file"
    chmod 600 "$token_file"
    prepare_novnc_web
    ensure_tls_cert
    start_websockify 6080 "$token_file"

    local i
    for i in $(seq 1 30); do
        DISPLAY=:1 xdpyinfo >/dev/null 2>&1 && break
        sleep 1
    done

    start_panel_keep_below
    echo "Virtual desktop ready: DISPLAY=:1 noVNC=:6080" >&2
}

main "$@"
