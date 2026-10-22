#!/bin/bash
# Container entrypoint: orchestrate only.
# Virtual desktop → scripts/start_vnc.sh; Chrome CDP starts after desktop is up.
set -euo pipefail

export HOME="${HOME:-/home/sandbox}"
export PATH="$HOME/.local/bin:$PATH"
export DISPLAY="${DISPLAY:-:1}"
export PLAYWRIGHT_CLI_SESSION="${PLAYWRIGHT_CLI_SESSION:-default}"
export SANDBOX_DISPLAY_WIDTH="${SANDBOX_DISPLAY_WIDTH:-1920}"
export SANDBOX_DISPLAY_HEIGHT="${SANDBOX_DISPLAY_HEIGHT:-1080}"

# shellcheck source=/dev/null
. "$HOME/.local/bin/chrome-cdp-runtime.sh"

CHROME_CDP_DIR="${CHROME_CDP_DIR:-/opt/google-chrome-cdp}"
CHROME_CDP_SEED="${CHROME_CDP_SEED:-/usr/local/share/google-chrome-cdp-seed}"

stop_port() {
    local port="$1"
    local pids pid
    pids=$(ss -ltnp "sport = :${port}" 2>/dev/null | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u)
    for pid in $pids; do
        kill "$pid" 2>/dev/null || true
    done
}

chrome_cdp_needs_seed() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        return 0
    fi
    if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
        return 0
    fi
    if [ ! -f "$dir/Default/Preferences" ]; then
        return 0
    fi
    return 1
}

prepare_chrome_profile() {
    mkdir -p /opt/downloads "$CHROME_CDP_DIR"
    if chrome_cdp_needs_seed "$CHROME_CDP_DIR"; then
        if [ -d "$CHROME_CDP_SEED" ]; then
            echo "Chrome CDP profile empty; cloning seed from $CHROME_CDP_SEED -> $CHROME_CDP_DIR" >&2
            cp -a "$CHROME_CDP_SEED"/. "$CHROME_CDP_DIR"/
        else
            echo "Chrome CDP seed missing at $CHROME_CDP_SEED; starting with empty profile" >&2
        fi
    else
        echo "Chrome CDP profile already present at $CHROME_CDP_DIR; skip seed clone" >&2
    fi
    if [ "$(id -u)" = "0" ]; then
        chown -R sandbox:sandbox /opt/downloads "$CHROME_CDP_DIR" 2>/dev/null || true
    fi
}

start_chrome_stack() {
    prepare_chrome_profile

    if ! cdp_ready; then
        start_chrome_cdp
    fi

    local i
    for i in $(seq 1 30); do
        cdp_ready && break
        sleep 1
    done

    if cdp_ready; then
        attach_playwright_cdp
    else
        echo "Chrome CDP did not start on 127.0.0.1:9222" >&2
    fi

    DISPLAY=:1 minimize_chrome_cdp_window >/dev/null 2>&1 || true

    stop_port 9333
    nohup env CDP_VIEW_TOKEN="$CDP_VIEW_TOKEN" \
        "$HOME/.local/bin/node" "$HOME/.local/bin/chrome-cdp-view.mjs" \
        > "$HOME/.config/cdp-view.log" 2>&1 &
    echo $! > "$HOME/.config/cdp-view.pid"

    "$HOME/.local/bin/chrome-cdp-monitor.sh" &
    echo $! > "$HOME/.config/chrome-cdp-monitor.pid"
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

    # Virtual desktop: only via start_vnc.sh
    if [ ! -x "$HOME/.local/bin/start_vnc.sh" ]; then
        echo "start_vnc.sh missing at $HOME/.local/bin/start_vnc.sh" >&2
        exit 1
    fi
    "$HOME/.local/bin/start_vnc.sh"

    start_chrome_stack

    echo "Public desktop: port 6080 (open the site root)"
    echo "Public Chrome view: port 9333"

    while true; do
        sleep 3600
    done
}

main "$@"
