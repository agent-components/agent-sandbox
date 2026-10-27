#!/bin/bash
# Shared Chrome CDP helpers (entrypoint + launch-chrome-cdp). Source only; do not exec.

# 与 chrome-cdp --user-data-dir 一致。
CHROME_CDP_DIR=/data/google-chrome

chrome_cdp_running() {
    pgrep -f "user-data-dir=${CHROME_CDP_DIR}" >/dev/null 2>&1
}

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

# Seed Bookmarks once from the baked tree (even when /data profile already exists).
# Downstream images / bind-mounts place Bookmarks at:
#   /usr/local/share/google-chrome-cdp/Default/Bookmarks
# After the first successful seed, leave the runtime Bookmarks alone (user may edit).
# Bookmark bar visibility belongs in Default/Preferences (cloned with the profile).
seed_chrome_bookmarks_once() {
    local src=/usr/local/share/google-chrome-cdp/Default/Bookmarks
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

# Clone baked defaults into /data when empty; seed Bookmarks at most once afterward.
prepare_chrome_profile() {
    local seed=/usr/local/share/google-chrome-cdp
    mkdir -p "$CHROME_CDP_DIR"
    if chrome_cdp_needs_default "$CHROME_CDP_DIR"; then
        if [ -d "$seed" ]; then
            echo "Chrome CDP profile empty; cloning default from $seed -> $CHROME_CDP_DIR" >&2
            cp -a "$seed"/. "$CHROME_CDP_DIR"/
        else
            echo "Chrome CDP default missing at $seed; starting with empty profile" >&2
        fi
    fi
    seed_chrome_bookmarks_once
}

# Drop leftover Chrome/CDP before a cold start (no auto-restart monitor).
# Only wipe Singleton* after processes are gone — clearing them while a start is
# in flight is what lets a second dock click spawn another Chrome.
clear_stale_chrome_cdp() {
    if [ -f "$HOME/.config/chrome-cdp.pid" ]; then
        kill "$(tr -d '[:space:]' < "$HOME/.config/chrome-cdp.pid")" 2>/dev/null || true
    fi
    local pids pid
    pids=$(ss -ltnp 'sport = :9222' 2>/dev/null | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u)
    for pid in $pids; do
        kill "$pid" 2>/dev/null || true
    done
    # Best-effort stop of any profile Chrome left without a listening CDP.
    pkill -f "user-data-dir=${CHROME_CDP_DIR}" 2>/dev/null || true
    local i=0
    while [ "$i" -lt 20 ]; do
        if ! chrome_cdp_running; then
            break
        fi
        i=$((i + 1))
        sleep 0.1
    done
    rm -f "$CHROME_CDP_DIR/SingletonLock" \
        "$CHROME_CDP_DIR/SingletonCookie" \
        "$CHROME_CDP_DIR/SingletonSocket"
}

attach_playwright_cdp() {
    npx --yes @playwright/cli detach >/dev/null 2>&1 || true
    npx --yes @playwright/cli attach --cdp=http://127.0.0.1:9222
}
