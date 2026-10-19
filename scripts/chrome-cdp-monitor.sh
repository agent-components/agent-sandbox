#!/bin/bash
export HOME=/home/apm
export PATH="/home/apm/.local/bin:$PATH"
export DISPLAY=:1
export PLAYWRIGHT_CLI_SESSION=default
cdp_ready() { curl -fsS --max-time 2 http://127.0.0.1:9222/json/version >/dev/null 2>&1; }
start_chrome_cdp() {
  if [ -f "$HOME/.config/chrome-cdp.pid" ]; then
    kill "$(tr -d '[:space:]' < "$HOME/.config/chrome-cdp.pid")" 2>/dev/null || true
  fi
  pids=$(ss -ltnp 'sport = :9222' 2>/dev/null | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u)
  for pid in $pids; do kill "$pid" 2>/dev/null || true; done
  sleep 1
  rm -f "$HOME/.config/google-chrome-cdp/SingletonLock" \
        "$HOME/.config/google-chrome-cdp/SingletonCookie" \
        "$HOME/.config/google-chrome-cdp/SingletonSocket"
  python3 "$HOME/.local/bin/seed-chrome-cdp-appearance.py" >>"$HOME/.config/chrome-cdp.log" 2>&1 || true
  nohup "$HOME/.local/bin/chrome-cdp" --no-first-run --no-default-browser-check about:blank \
    >>"$HOME/.config/chrome-cdp.log" 2>&1 &
  echo $! >"$HOME/.config/chrome-cdp.pid"
}
ensure_chrome_cdp() {
  if cdp_ready; then return 0; fi
  echo "Chrome CDP unavailable; restarting..." >&2
  start_chrome_cdp
  for i in $(seq 1 30); do cdp_ready && break; sleep 1; done
  if cdp_ready; then
    playwright-cli detach >/dev/null 2>&1 || true
    playwright-cli attach --cdp=http://127.0.0.1:9222 || true
  fi
}
echo $$ >"$HOME/.config/chrome-cdp-monitor.pid"
while true; do sleep 5; ensure_chrome_cdp || true; done
