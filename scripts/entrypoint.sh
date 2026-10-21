#!/bin/bash

export HOME="${HOME:-/home/sandbox}"
export PATH="$HOME/.local/bin:$PATH"
export DISPLAY="${DISPLAY:-:1}"
export PLAYWRIGHT_CLI_SESSION="${PLAYWRIGHT_CLI_SESSION:-default}"
# Desktop / Chrome window size (CDP viewport tracks this). Defaults 1920x1080.
export SANDBOX_DISPLAY_WIDTH="${SANDBOX_DISPLAY_WIDTH:-1920}"
export SANDBOX_DISPLAY_HEIGHT="${SANDBOX_DISPLAY_HEIGHT:-1080}"

display_ready() {
    DISPLAY=:1 xdpyinfo >/dev/null 2>&1
}

stop_port() {
    local port="$1"
    local pids
    pids=$(ss -ltnp "sport = :${port}" 2>/dev/null | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u)
    local pid
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
    # Prefer sandbox-desktop vnc_lite: hidden noVNC top_bar + clipboard paste UI.
    # Falls back to package file with only #top_bar hidden.
    rm -f "$web_root/vnc_lite.html"
    if [ -f "$custom_lite" ]; then
        cp "$custom_lite" "$web_root/vnc_lite.html"
    elif [ -f /usr/share/novnc/vnc_lite.html ]; then
        cp /usr/share/novnc/vnc_lite.html "$web_root/vnc_lite.html"
        sed -i 's|#top_bar {|#top_bar { display: none !important;|' \
            "$web_root/vnc_lite.html"
    fi
    # Do NOT embed NOVNC_TOKEN in anonymously downloadable HTML/JS.
    # WebSocket still requires TokenFile; client must supply token in path.
    cat > "$web_root/index.html" << 'EOFINNER'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <title>Desktop</title>
  <script>
    // Redirect without token. Set Settings → path to:
    //   websockify?token=YOUR_NOVNC_TOKEN
    // or open vnc_lite.html with path=websockify%3Ftoken%3D...
    location.replace("vnc_lite.html?reconnect=1&resize=scale&path=" + encodeURIComponent("websockify"));
  </script>
</head>
<body></body>
</html>
EOFINNER
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

start_novnc() {
    local port="$1"
    local token_file="$2"
    stop_port "$port"
    nohup websockify --web="$HOME/.vnc/novnc-web" \
        --cert="$HOME/.vnc/self.crt" --key="$HOME/.vnc/self.key" \
        --token-plugin TokenFile --token-source "$token_file" \
        --heartbeat=30 \
        "0.0.0.0:${port}" \
        > "$HOME/.vnc/novnc-${port}.log" 2>&1 &
    echo $! > "$HOME/.vnc/novnc-${port}.pid"
}

# Seed XFCE so panel/desktop open /home/workspace (not $HOME).
# Tokens stay env-only; this only writes UI shortcuts.
seed_xfce_workspace_ui() {
    local seed="$HOME/.config/xfce-seed"
    local panel_dir="$HOME/.config/xfce4/panel"
    local xfconf_dir="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    local apps=/usr/share/applications
    mkdir -p "$HOME/Desktop" "$xfconf_dir" \
        "$HOME/.local/share/applications" \
        "$HOME/.local/share/xfce4/helpers" \
        "$HOME/.config/xfce4" \
        "$panel_dir/launcher-13" "$panel_dir/launcher-14" \
        "$panel_dir/launcher-15"
    # Drop old panel launcher dirs (e.g. appfinder launcher-16) from prior seeds
    rm -rf "$panel_dir/launcher-16" "$panel_dir/launcher-17" "$panel_dir/launcher-18"

    if [ -f "$seed/xfconf/xfce4-panel.xml" ]; then
        cp -f "$seed/xfconf/xfce4-panel.xml" "$xfconf_dir/xfce4-panel.xml"
    fi
    if [ -f "$seed/xfconf/xfce4-desktop.xml" ]; then
        cp -f "$seed/xfconf/xfce4-desktop.xml" "$xfconf_dir/xfce4-desktop.xml"
    fi

    # Preferred Web Browser + MIME -> chrome-cdp (same user-data-dir / :9222)
    if [ -f "$seed/applications/chrome-cdp.desktop" ]; then
        cp -f "$seed/applications/chrome-cdp.desktop" \
            "$HOME/.local/share/applications/chrome-cdp.desktop"
    fi
    if [ -f "$seed/helpers/chrome-cdp.desktop" ]; then
        cp -f "$seed/helpers/chrome-cdp.desktop" \
            "$HOME/.local/share/xfce4/helpers/chrome-cdp.desktop"
    fi
    if [ -f "$seed/helpers.rc" ]; then
        cp -f "$seed/helpers.rc" "$HOME/.config/xfce4/helpers.rc"
    else
        printf '%s\n' 'WebBrowser=chrome-cdp' > "$HOME/.config/xfce4/helpers.rc"
    fi
    if [ -f "$seed/mimeapps.list" ]; then
        cp -f "$seed/mimeapps.list" "$HOME/.config/mimeapps.list"
    fi

    # Panel launcher .desktop files (filenames must match xfce4-panel.xml items)
    # plugin-13: terminal
    rm -f "$panel_dir/launcher-13/"*
    if [ -f "$seed/panel/launcher-terminal/xfce4-terminal.desktop" ]; then
        cp -f "$seed/panel/launcher-terminal/xfce4-terminal.desktop" \
            "$panel_dir/launcher-13/xfce4-terminal.desktop"
    elif [ -f "$apps/xfce4-terminal.desktop" ]; then
        cp -f "$apps/xfce4-terminal.desktop" "$panel_dir/launcher-13/xfce4-terminal.desktop"
    elif [ -f "$apps/xfce4-terminal-emulator.desktop" ]; then
        cp -f "$apps/xfce4-terminal-emulator.desktop" \
            "$panel_dir/launcher-13/xfce4-terminal.desktop"
    fi
    # plugin-14: workspace files
    if [ -f "$seed/panel/launcher-workspace/workspace-files.desktop" ]; then
        cp -f "$seed/panel/launcher-workspace/workspace-files.desktop" \
            "$panel_dir/launcher-14/workspace-files.desktop"
    fi
    # plugin-15: chrome-cdp wrapper (not exo WebBrowser / default profile)
    rm -f "$panel_dir/launcher-15/"*
    if [ -f "$seed/panel/launcher-chrome/chrome-cdp.desktop" ]; then
        cp -f "$seed/panel/launcher-chrome/chrome-cdp.desktop" \
            "$panel_dir/launcher-15/chrome-cdp.desktop"
    elif [ -f "$seed/applications/chrome-cdp.desktop" ]; then
        cp -f "$seed/applications/chrome-cdp.desktop" \
            "$panel_dir/launcher-15/chrome-cdp.desktop"
    fi

    if [ -f "$seed/workspace.desktop" ]; then
        cp -f "$seed/workspace.desktop" "$HOME/Desktop/workspace.desktop"
        chmod 644 "$HOME/Desktop/workspace.desktop"
    fi
    # Drop any leftover Home icon path from a prior session
    rm -f "$HOME/.config/xfce4/desktop/icons.screen0.yaml"
    # Keep ~/.config/google-chrome as the UI reference profile (theme/GTK/sidebar).
    # Panel / default browser still use chrome-cdp (CDP on :9222); do not wipe normal.
}

# Sync appearance prefs from normal Chrome profile into CDP profile so CDP looks
# like the confirmed-good UI (classic frame, not GTK system theme), while keeping
# a separate user-data-dir for remote debugging.
seed_chrome_cdp_appearance() {
    mkdir -p /opt/google-chrome-cdp/Default
    if [ -x "$HOME/.local/bin/seed-chrome-cdp-appearance.py" ] || [ -f "$HOME/.local/bin/seed-chrome-cdp-appearance.py" ]; then
        python3 "$HOME/.local/bin/seed-chrome-cdp-appearance.py" || true
    else
        echo "seed-chrome-cdp-appearance.py missing; skipping UI seed" >&2
    fi
}


# Chrome Default download path is /opt/downloads (prefs seeded below).
# CDP user-data-dir lives under /opt (persist volume). Build-time seed lives
# outside /opt at /usr/local/share/google-chrome-cdp-seed so an empty /opt
# mount cannot wipe defaults; we clone the seed only when the runtime dir
# is missing, empty, or lacks Default/Preferences.
CHROME_CDP_DIR="${CHROME_CDP_DIR:-/opt/google-chrome-cdp}"
CHROME_CDP_SEED="${CHROME_CDP_SEED:-/usr/local/share/google-chrome-cdp-seed}"

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

prepare_chrome_downloads() {
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
    # Entrypoint usually runs as sandbox; chown when root (e.g. child image root entry).
    if [ "$(id -u)" = "0" ]; then
        chown -R sandbox:sandbox /opt/downloads "$CHROME_CDP_DIR" 2>/dev/null || true
    fi
}

cdp_ready() {
    curl -fsS --max-time 2 http://127.0.0.1:9222/json/version >/dev/null 2>&1
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
    # Align CDP profile appearance with normal Chrome UI before launch.
    seed_chrome_cdp_appearance
    DISPLAY=:1 nohup "$HOME/.local/bin/chrome-cdp" \
        --no-first-run --no-default-browser-check about:blank \
        > "$HOME/.config/chrome-cdp.log" 2>&1 &
    echo $! > "$HOME/.config/chrome-cdp.pid"
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
        return 0
    fi
    echo "Chrome CDP did not recover on 127.0.0.1:9222" >&2
    return 1
}

monitor_chrome_cdp() {
    # Prefer dedicated script (safer than pkill -f matching the entrypoint cmdline).
    if [ -f "$HOME/.local/bin/chrome-cdp-monitor.sh" ]; then
        exec "$HOME/.local/bin/chrome-cdp-monitor.sh"
    fi
    while true; do
        sleep 5
        ensure_chrome_cdp || true
    done
}

start_desktop() {
    echo "Starting remote desktop, Chrome, and playwright-cli..."
    mkdir -p "$HOME/.vnc" "$HOME/.config"
    prepare_chrome_downloads

    if [ -z "${NOVNC_TOKEN:-}" ]; then
        echo "NOVNC_TOKEN is required" >&2
        exit 1
    fi
    if [ -z "${CDP_VIEW_TOKEN:-}" ]; then
        echo "CDP_VIEW_TOKEN is required" >&2
        exit 1
    fi

    seed_xfce_workspace_ui

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
        # Fixed desktop name: no hostname/username in noVNC title
        vncserver :1 -localhost yes \
            -geometry "${SANDBOX_DISPLAY_WIDTH}x${SANDBOX_DISPLAY_HEIGHT}" -depth 24 \
            -SecurityTypes None -desktop Desktop
    fi

    local token_file="$HOME/.vnc/novnc-targets"
    printf '%s: 127.0.0.1:5901\n' "$NOVNC_TOKEN" > "$token_file"
    chmod 600 "$token_file"
    prepare_novnc_web
    ensure_tls_cert
    start_novnc 6080 "$token_file"

    local i
    for i in $(seq 1 30); do
        DISPLAY=:1 xdpyinfo >/dev/null 2>&1 && break
        sleep 1
    done

    if ! cdp_ready; then
        start_chrome_cdp
    fi

    for i in $(seq 1 30); do
        cdp_ready && break
        sleep 1
    done

    if cdp_ready; then
        attach_playwright_cdp
    else
        echo "Chrome CDP did not start on 127.0.0.1:9222" >&2
    fi

    stop_port 9333
    nohup env CDP_VIEW_TOKEN="$CDP_VIEW_TOKEN" \
        "$HOME/.local/bin/node" "$HOME/.local/bin/chrome-cdp-view.mjs" \
        > "$HOME/.config/cdp-view.log" 2>&1 &
    echo $! > "$HOME/.config/cdp-view.pid"

    # Keep CDP alive: closing the last Chrome window exits the process and drops 9222.
    monitor_chrome_cdp &
    echo $! > "$HOME/.config/chrome-cdp-monitor.pid"

    echo "Public desktop: port 6080 (open the site root)"
    echo "Public Chrome view: port 9333"
}

start_desktop

# The desktop processes run in the background. Stay alive so the container
# does not exit and stop them.
while true; do
    sleep 3600
done
