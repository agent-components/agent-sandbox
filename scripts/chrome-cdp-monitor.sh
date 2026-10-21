#!/bin/bash
export HOME=/home/sandbox
export PATH="/home/sandbox/.local/bin:$PATH"
export DISPLAY=:1
export PLAYWRIGHT_CLI_SESSION=default
cdp_ready() { curl -fsS --max-time 2 http://127.0.0.1:9222/json/version >/dev/null 2>&1; }
minimize_chrome_cdp_window() {
  local i wid state
  local hidden_streak=0
  for i in $(seq 1 60); do
    wid=$(wmctrl -lx 2>/dev/null | awk '
      BEGIN { IGNORECASE = 1 }
      /\.Google-chrome-cdp[[:space:]]/ { print $1; exit }
    ')
    if [ -n "$wid" ]; then
      if ! wmctrl -i -r "$wid" -b add,hidden 2>/dev/null; then
        if command -v xdotool >/dev/null 2>&1; then
          xdotool windowminimize "$(printf '%d' "$wid" 2>/dev/null || echo 0)" 2>/dev/null || true
        fi
      fi
      state=$(xprop -id "$wid" _NET_WM_STATE 2>/dev/null || true)
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
      state=$(xprop -id "$wid" WM_STATE 2>/dev/null || true)
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
  if [ -f "$HOME/.config/chrome-cdp.pid" ]; then
    kill "$(tr -d '[:space:]' < "$HOME/.config/chrome-cdp.pid")" 2>/dev/null || true
  fi
  pids=$(ss -ltnp 'sport = :9222' 2>/dev/null | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u)
  for pid in $pids; do kill "$pid" 2>/dev/null || true; done
  sleep 1
  rm -f "/opt/google-chrome-cdp/SingletonLock" \
        "/opt/google-chrome-cdp/SingletonCookie" \
        "/opt/google-chrome-cdp/SingletonSocket"
  python3 "$HOME/.local/bin/seed-chrome-cdp-appearance.py" >>"$HOME/.config/chrome-cdp.log" 2>&1 || true
  nohup "$HOME/.local/bin/chrome-cdp" --no-first-run --no-default-browser-check about:blank \
    >>"$HOME/.config/chrome-cdp.log" 2>&1 &
  echo $! >"$HOME/.config/chrome-cdp.pid"
  # Same as entrypoint: start minimized; dock toggle is separate.
  minimize_chrome_cdp_window >/dev/null 2>&1 &
}
ensure_chrome_cdp() {
  if cdp_ready; then return 0; fi
  echo "Chrome CDP unavailable; restarting..." >&2
  start_chrome_cdp
  for i in $(seq 1 30); do cdp_ready && break; sleep 1; done
  if cdp_ready; then
    playwright-cli detach >/dev/null 2>&1 || true
    playwright-cli attach --cdp=http://127.0.0.1:9222 || true
    # attach may raise the window; keep entrypoint Chrome minimized
    minimize_chrome_cdp_window >/dev/null 2>&1 || true
  fi
}
echo $$ >"$HOME/.config/chrome-cdp-monitor.pid"
while true; do sleep 5; ensure_chrome_cdp || true; done
