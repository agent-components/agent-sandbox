#!/bin/bash
# Container entrypoint: desktop via start_vnc.sh.
# Chrome/CDP: dock on demand, or boot auto-start when SANDBOX_AUTO_START_CHROME=1.
set -euo pipefail

# Mounted /data may be empty; create dirs.
sh /tmp/install-data-links.sh

export SANDBOX_DISPLAY_WIDTH="${SANDBOX_DISPLAY_WIDTH:-1920}"
export SANDBOX_DISPLAY_HEIGHT="${SANDBOX_DISPLAY_HEIGHT:-1080}"

# shellcheck source=/dev/null
. "$HOME/.local/bin/chrome-cdp-runtime.sh"

stop_port() {
    local port="$1"
    local pids pid
    pids=$(ss -ltnp "sport = :${port}" 2>/dev/null | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u)
    for pid in $pids; do
        kill "$pid" 2>/dev/null || true
    done
}

want_auto_start_chrome() {
    [ "${SANDBOX_AUTO_START_CHROME:-0}" = "1" ]
}

main() {
    echo "Starting sandbox desktop..."
    mkdir -p "$HOME/.vnc" "$HOME/.config" \
        "$LOG_DIR/chrome-cdp" "$LOG_DIR/cdp-view" "$LOG_DIR/novnc" "$LOG_DIR/panel"

    if [ -z "${NOVNC_TOKEN:-}" ]; then
        echo "NOVNC_TOKEN is required" >&2
        exit 1
    fi
    if [ -z "${CDP_VIEW_TOKEN:-}" ]; then
        echo "CDP_VIEW_TOKEN is required" >&2
        exit 1
    fi

    if [ ! -x "$HOME/.local/bin/start_vnc.sh" ]; then
        echo "start_vnc.sh missing at $HOME/.local/bin/start_vnc.sh" >&2
        exit 1
    fi
    "$HOME/.local/bin/start_vnc.sh"

    # Profile ready for dock or boot auto-start.
    prepare_chrome_profile

    # MJPEG view waits until Chrome (and CDP) are up.
    stop_port 9333
    nohup env CDP_VIEW_TOKEN="$CDP_VIEW_TOKEN" \
        "$HOME/.local/bin/node" "$HOME/.local/bin/chrome-cdp-view.mjs" \
        > "$LOG_DIR/cdp-view/cdp-view.log" 2>&1 &
    echo $! > "$HOME/.config/cdp-view.pid"

    if want_auto_start_chrome; then
        echo "SANDBOX_AUTO_START_CHROME enabled; launching Chrome CDP..."
        if [ ! -x "$HOME/.local/bin/launch-chrome-cdp" ]; then
            echo "launch-chrome-cdp missing at $HOME/.local/bin/launch-chrome-cdp" >&2
            exit 1
        fi
        "$HOME/.local/bin/launch-chrome-cdp"
        echo "Chrome CDP auto-started; view :9333"
    else
        echo "Chrome CDP starts when dock launches Chrome; view :9333 after that"
    fi

    echo "Public desktop: port 6080"

    while true; do
        sleep 3600
    done
}

main "$@"
