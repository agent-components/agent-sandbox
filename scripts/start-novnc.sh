#!/bin/sh
set -eu
W="${SANDBOX_DISPLAY_WIDTH:-1920}"
H="${SANDBOX_DISPLAY_HEIGHT:-1080}"
mkdir -p "$HOME/.vnc"
if ! vncserver -list 2>/dev/null | awk 'NR>4 && $1=="1" { found=1 } END { exit !found }'; then
  vncserver :1 -localhost yes -geometry "${W}x${H}" -depth 24
fi
if ! ss -ltn | awk '{print $4}' | grep -q ':6080$'; then
  nohup websockify --web=/usr/share/novnc/ 0.0.0.0:6080 localhost:5901 > "$HOME/.vnc/novnc.log" 2>&1 &
  echo $! > "$HOME/.vnc/novnc.pid"
fi
echo "noVNC: http://127.0.0.1:6080/vnc.html"
echo "DISPLAY=:1 geometry=${W}x${H}"
