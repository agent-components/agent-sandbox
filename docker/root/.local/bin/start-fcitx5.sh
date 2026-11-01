#!/bin/sh
# XFCE autostart: Fcitx5 on the session bus. Do not pass -d (that disables addons).
. /root/.local/bin/sandbox-gui-env.sh
i=0
while [ "$i" -lt 50 ]; do
    _sandbox_probe_session_bus
    [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && break
    i=$((i + 1))
    sleep 0.1
done
# Stay up for the session. fcitx5 runs in the foreground; restart if it exits.
while true; do
    fcitx5 -r || true
    sleep 2
done
