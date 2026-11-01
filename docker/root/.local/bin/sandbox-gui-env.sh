#!/bin/sh
# GUI environment: Fcitx5 pinyin + zh_CN for the desktop session.
# Source from xstartup and from launchers started outside the session
# (SSH / agent). Do not exec.
#
# Container ENV LANG stays C.UTF-8. This file forces zh_CN only for GUI
# processes that source it. Set SANDBOX_WAIT_FOR_SESSION_BUS=1 to poll
# until xfce4-session publishes DBUS_SESSION_BUS_ADDRESS (Chrome/terminal
# started from SSH, before the panel has finished starting).

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
export INPUT_METHOD=fcitx
export LANG=zh_CN.UTF-8
export LC_CTYPE=zh_CN.UTF-8
unset LC_ALL

_sandbox_probe_session_bus() {
    if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        return 0
    fi
    _pid="$(pgrep -n -x xfce4-session 2>/dev/null || true)"
    if [ -n "$_pid" ] && [ -r "/proc/${_pid}/environ" ]; then
        _dbus="$(tr '\0' '\n' < "/proc/${_pid}/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -n 1)"
        if [ -n "$_dbus" ]; then
            export DBUS_SESSION_BUS_ADDRESS="$_dbus"
        fi
    fi
    unset _pid _dbus
}

_sandbox_probe_session_bus
if [ "${SANDBOX_WAIT_FOR_SESSION_BUS:-0}" = "1" ]; then
    _i=0
    while [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ "$_i" -lt 50 ]; do
        _i=$((_i + 1))
        sleep 0.1
        _sandbox_probe_session_bus
    done
    unset _i
fi
