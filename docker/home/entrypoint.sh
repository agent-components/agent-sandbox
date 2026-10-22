#!/bin/bash
# Container entrypoint: desktop via start_vnc.sh; Chrome/CDP only when dock launches it.
set -euo pipefail

export HOME="${HOME:-/home/sandbox}"
export PATH="$HOME/.local/bin:$PATH"
export LANG="${LANG:-C.UTF-8}"
export DISPLAY="${DISPLAY:-:1}"
export PLAYWRIGHT_CLI_SESSION="${PLAYWRIGHT_CLI_SESSION:-default}"
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

main() {
    echo "Starting sandbox desktop..."
    mkdir -p "$HOME/.vnc" "$HOME/.config"

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

    # Profile ready for first dock click; do not start Chrome/CDP here.
    prepare_chrome_profile

    # MJPEG view waits until Chrome (and CDP) are started from the dock.
    stop_port 9333
    nohup env CDP_VIEW_TOKEN="$CDP_VIEW_TOKEN" \
        "$HOME/.local/bin/node" "$HOME/.local/bin/chrome-cdp-view.mjs" \
        > "$HOME/.config/cdp-view.log" 2>&1 &
    echo $! > "$HOME/.config/cdp-view.pid"

    echo "Public desktop: port 6080"
    echo "Chrome CDP starts when dock launches Chrome; view :9333 after that"

    while true; do
        sleep 3600
    done
}

main "$@"
