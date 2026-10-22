#!/bin/bash
# Shared Chrome CDP helpers for entrypoint.sh and chrome-cdp-monitor.sh.
# Source this file; do not exec it.

export HOME="${HOME:-/home/sandbox}"
export PATH="$HOME/.local/bin:$PATH"
export DISPLAY="${DISPLAY:-:1}"
export PLAYWRIGHT_CLI_SESSION="${PLAYWRIGHT_CLI_SESSION:-default}"

cdp_ready() {
    curl -fsS --max-time 2 http://127.0.0.1:9222/json/version >/dev/null 2>&1
}

# Minimize CDP Chrome once its X window appears. Entrypoint default start should
# not cover the desktop; dock toggle remains launch-chrome-cdp / single-instance.
# CDP on :9222 is unaffected (process + debugging port stay up).
# Re-applies through map/focus races (Chrome remap, playwright-cli attach).
# Requires HIDDEN/Iconic to hold for a short settle window before success.
minimize_chrome_cdp_window() {
    local i wid state
    local display="${DISPLAY:-:1}"
    local hidden_streak=0
    # ~15s total; need ~2s continuous hidden (8 * 0.25)
    for i in $(seq 1 60); do
        wid=$(DISPLAY="$display" wmctrl -lx 2>/dev/null | awk '
            BEGIN { IGNORECASE = 1 }
            /\.Google-chrome-cdp[[:space:]]/ { print $1; exit }
        ')
        if [ -n "$wid" ]; then
            if ! DISPLAY="$display" wmctrl -i -r "$wid" -b add,hidden 2>/dev/null; then
                if command -v xdotool >/dev/null 2>&1; then
                    DISPLAY="$display" xdotool windowminimize "$(printf '%d' "$wid" 2>/dev/null || echo 0)" 2>/dev/null || true
                fi
            fi
            state=$(DISPLAY="$display" xprop -id "$wid" _NET_WM_STATE 2>/dev/null || true)
            case "$state" in
                *_NET_WM_STATE_HIDDEN*)
                    hidden_streak=$((hidden_streak + 1))
                    if [ "$hidden_streak" -ge 8 ]; then
                        return 0
                    fi
                    sleep 0.25
                    continue
                    ;;
            esac
            state=$(DISPLAY="$display" xprop -id "$wid" WM_STATE 2>/dev/null || true)
            case "$state" in
                *Iconic*)
                    hidden_streak=$((hidden_streak + 1))
                    if [ "$hidden_streak" -ge 8 ]; then
                        return 0
                    fi
                    sleep 0.25
                    continue
                    ;;
            esac
        fi
        hidden_streak=0
        sleep 0.25
    done
    return 1
}

start_chrome_cdp() {
    # Stop any leftover CDP Chrome so 9222 can be rebound.
    if [ -f "$HOME/.config/chrome-cdp.pid" ]; then
        kill "$(tr -d '[:space:]' < "$HOME/.config/chrome-cdp.pid")" 2>/dev/null || true
    fi
    # Prefer killing by listen port (avoids pkill -f matching this script's argv).
    local pids pid
    pids=$(ss -ltnp 'sport = :9222' 2>/dev/null | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u)
    for pid in $pids; do
        kill "$pid" 2>/dev/null || true
    done
    sleep 1
    # Drop stale singleton locks so a fresh Chrome can bind 9222.
    rm -f /opt/google-chrome-cdp/SingletonLock \
        /opt/google-chrome-cdp/SingletonCookie \
        /opt/google-chrome-cdp/SingletonSocket
    DISPLAY=:1 nohup "$HOME/.local/bin/chrome-cdp" \
        --no-first-run --no-default-browser-check about:blank \
        > "$HOME/.config/chrome-cdp.log" 2>&1 &
    echo $! > "$HOME/.config/chrome-cdp.pid"
    # Initial start minimized (not dock click toggle). Window may appear after
    # process start; poll in background so CDP wait is not blocked.
    DISPLAY=:1 minimize_chrome_cdp_window >/dev/null 2>&1 &
}

attach_playwright_cdp() {
    playwright-cli detach >/dev/null 2>&1 || true
    playwright-cli attach --cdp=http://127.0.0.1:9222
}

ensure_chrome_cdp() {
    if cdp_ready; then
        return 0
    fi
    echo "Chrome CDP unavailable on 127.0.0.1:9222; restarting chrome-cdp..." >&2
    start_chrome_cdp
    local i
    for i in $(seq 1 30); do
        cdp_ready && break
        sleep 1
    done
    if cdp_ready; then
        attach_playwright_cdp || true
        DISPLAY=:1 minimize_chrome_cdp_window >/dev/null 2>&1 || true
        return 0
    fi
    echo "Chrome CDP did not recover on 127.0.0.1:9222" >&2
    return 1
}
