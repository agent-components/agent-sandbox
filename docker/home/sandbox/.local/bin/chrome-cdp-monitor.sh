#!/bin/bash
# Keep CDP alive: closing the last Chrome window exits the process and drops 9222.
# Logic lives in chrome-cdp-runtime.sh (shared with entrypoint).
export HOME="${HOME:-/home/sandbox}"
# shellcheck source=/dev/null
. "$HOME/.local/bin/chrome-cdp-runtime.sh"

echo $$ >"$HOME/.config/chrome-cdp-monitor.pid"
while true; do
    sleep 5
    ensure_chrome_cdp || true
done
