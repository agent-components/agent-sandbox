#!/usr/bin/env bash
# Keep the XFCE bottom dock under maximized/fullscreen clients.
#
# enable-struts=false already makes _NET_WORKAREA full-screen, so Chrome
# maximizes to full SANDBOX_DISPLAY geometry — but xfce4-panel still uses
# _NET_WM_WINDOW_TYPE_DOCK, so xfwm4 stacks it above normal windows.
# Force _NET_WM_STATE_BELOW (and demote TYPE to NORMAL) so maximize/fullscreen
# paint over the dock. Panel stays mapped for clicks when nothing covers it.
set -euo pipefail

DISPLAY="${DISPLAY:-:1}"
export DISPLAY

INTERVAL_SEC="${PANEL_KEEP_BELOW_INTERVAL:-3}"
ONCE=0
if [ "${1:-}" = "--once" ]; then
  ONCE=1
fi

panel_dock_ids() {
  # Prefer the mapped DOCK (or former DOCK) frame that wmctrl lists.
  wmctrl -lx 2>/dev/null | awk 'tolower($0) ~ /xfce4-panel\.xfce4-panel/ { print $1 }'
}

needs_fix() {
  local id="$1"
  local typ state
  typ=$(xprop -id "$id" _NET_WM_WINDOW_TYPE 2>/dev/null || true)
  state=$(xprop -id "$id" _NET_WM_STATE 2>/dev/null || true)
  # Apply when still DOCK, or when BELOW is missing.
  if echo "$typ" | grep -q '_NET_WM_WINDOW_TYPE_DOCK'; then
    return 0
  fi
  if ! echo "$state" | grep -q '_NET_WM_STATE_BELOW'; then
    return 0
  fi
  return 1
}

apply_one() {
  local id="$1"
  # Demote out of the WM dock layer so BELOW is honored for maximize.
  xprop -id "$id" -f _NET_WM_WINDOW_TYPE 32a \
    -set _NET_WM_WINDOW_TYPE _NET_WM_WINDOW_TYPE_NORMAL >/dev/null 2>&1 || true
  wmctrl -i -r "$id" -b add,below,sticky,skip_taskbar,skip_pager >/dev/null 2>&1 || true
  # Clear any ABOVE that panel/WM may have set.
  wmctrl -i -r "$id" -b remove,above >/dev/null 2>&1 || true
}

apply_all() {
  local id fixed=0
  for id in $(panel_dock_ids); do
    if needs_fix "$id"; then
      apply_one "$id"
      fixed=$((fixed + 1))
    fi
  done
  return 0
}

if [ "$ONCE" -eq 1 ]; then
  apply_all
  exit 0
fi

# Wait for panel to appear after startxfce4, then keep it below.
for _ in $(seq 1 60); do
  if [ -n "$(panel_dock_ids)" ]; then
    break
  fi
  sleep 1
done

while true; do
  apply_all || true
  sleep "$INTERVAL_SEC"
done
