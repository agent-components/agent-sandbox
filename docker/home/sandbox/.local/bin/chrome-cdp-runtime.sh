#!/bin/bash
# Shared Chrome CDP helpers (entrypoint + launch-chrome-cdp). Source only; do not exec.

export HOME="${HOME:-/home/sandbox}"
export PATH="$HOME/.local/bin:$PATH"
export DISPLAY="${DISPLAY:-:1}"
export PLAYWRIGHT_CLI_SESSION="${PLAYWRIGHT_CLI_SESSION:-default}"
export PLAYWRIGHT_MCP_OUTPUT_DIR="${PLAYWRIGHT_MCP_OUTPUT_DIR:-/opt/playwright-cli}"
export PLAYWRIGHT_DAEMON_SESSION_DIR="${PLAYWRIGHT_DAEMON_SESSION_DIR:-/opt/playwright-cli/daemon}"

CHROME_CDP_DIR="${CHROME_CDP_DIR:-/opt/google-chrome-cdp}"
CHROME_CDP_DEFAULT="${CHROME_CDP_DEFAULT:-/usr/local/share/google-chrome-cdp}"

cdp_ready() {
    curl -fsS --max-time 2 http://127.0.0.1:9222/json/version >/dev/null 2>&1
}

chrome_cdp_needs_default() {
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

# Seed Bookmarks once from the default tree (even when /opt profile already exists).
# Downstream images / bind-mounts place Bookmarks at:
#   $CHROME_CDP_DEFAULT/Default/Bookmarks
# After the first successful seed, leave the runtime Bookmarks alone (user may edit).
# Bookmark bar visibility belongs in Default/Preferences (cloned with the profile).
seed_chrome_bookmarks_once() {
    local src="$CHROME_CDP_DEFAULT/Default/Bookmarks"
    local dst="$CHROME_CDP_DIR/Default/Bookmarks"
    local stamp="$CHROME_CDP_DIR/.bookmarks-seeded"

    # Already seeded (or legacy hash stamp from earlier sync logic).
    if [ -f "$stamp" ] || [ -f "$CHROME_CDP_DIR/.bookmarks-seed-sha" ]; then
        [ -f "$stamp" ] || : >"$stamp"
        return 0
    fi
    if [ ! -f "$src" ]; then
        return 0
    fi

    mkdir -p "$CHROME_CDP_DIR/Default"
    cp -a "$src" "$dst"
    : >"$stamp"
    echo "Chrome CDP seeded Bookmarks once from $src -> $dst" >&2
}

# Clone baked defaults into /opt when empty; seed Bookmarks at most once afterward.
prepare_chrome_profile() {
    mkdir -p /opt/downloads "$CHROME_CDP_DIR"
    if chrome_cdp_needs_default "$CHROME_CDP_DIR"; then
        if [ -d "$CHROME_CDP_DEFAULT" ]; then
            echo "Chrome CDP profile empty; cloning default from $CHROME_CDP_DEFAULT -> $CHROME_CDP_DIR" >&2
            cp -a "$CHROME_CDP_DEFAULT"/. "$CHROME_CDP_DIR"/
        else
            echo "Chrome CDP default missing at $CHROME_CDP_DEFAULT; starting with empty profile" >&2
        fi
    fi
    seed_chrome_bookmarks_once
    if [ "$(id -u)" = "0" ]; then
        chown -R sandbox:sandbox /opt/downloads "$CHROME_CDP_DIR" 2>/dev/null || true
    fi
}

# Drop leftover Chrome/CDP before a cold start (no auto-restart monitor).
clear_stale_chrome_cdp() {
    if [ -f "$HOME/.config/chrome-cdp.pid" ]; then
        kill "$(tr -d '[:space:]' < "$HOME/.config/chrome-cdp.pid")" 2>/dev/null || true
    fi
    local pids pid
    pids=$(ss -ltnp 'sport = :9222' 2>/dev/null | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u)
    for pid in $pids; do
        kill "$pid" 2>/dev/null || true
    done
    sleep 1
    rm -f "$CHROME_CDP_DIR/SingletonLock" \
        "$CHROME_CDP_DIR/SingletonCookie" \
        "$CHROME_CDP_DIR/SingletonSocket"
}

attach_playwright_cdp() {
    npx --yes @playwright/cli detach >/dev/null 2>&1 || true
    npx --yes @playwright/cli attach --cdp=http://127.0.0.1:9222
}
