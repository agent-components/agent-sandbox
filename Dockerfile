# syntax=docker/dockerfile:1
# Local desktop image aligned with boat sandbox layout, username sandbox (uid 1000).
# Build: docker build --platform linux/amd64 -t local/agent-sandbox:0.1.0 .
FROM debian:trixie-slim

ENV HOME=/home/sandbox \
    USER=sandbox

# sandbox user uid 1000; WORKDIR tree /home/workspace (code only).
# /opt links are created at start by entrypoint → install-opt-links.sh (as root).
RUN useradd -m -u 1000 -s /bin/bash sandbox \
    && mkdir -p /home/workspace \
    && chown -R sandbox:sandbox /home/sandbox /home/workspace

COPY --chown=sandbox:sandbox docker/home/ /home/
COPY docker/usr/local/share/google-chrome-cdp/ /usr/local/share/google-chrome-cdp/
COPY docker/etc/xdg/xfce4/kiosk/ /etc/xdg/xfce4/kiosk/
COPY docker/tmp/ /tmp/

# Bind prefetched Chrome/Node from vendor (not image layers), then run the install scripts in /tmp.
RUN --mount=type=bind,source=vendor,target=/mnt/vendor,ro \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/root/.npm,sharing=locked \
    chmod 755 /tmp/use-debian-mirror.sh /tmp/install-*.sh \
 && /tmp/install-desktop-apt.sh \
 && /tmp/install-node.sh \
 && /tmp/install-chrome.sh \
 && chmod -R a+rX /home/sandbox/.local/bin \
 && chmod 755 /home/sandbox/.vnc/xstartup /home/sandbox/.config/tigervnc/xstartup \
 && chown -R sandbox:sandbox /home/sandbox /home/workspace /usr/local/share/google-chrome-cdp

EXPOSE 6080 9333

# Root only so entrypoint can chown a mounted /opt; it then drops to sandbox.
WORKDIR /home/workspace
ENV PATH="/home/sandbox/.local/bin:/home/sandbox/.local/node-v24/bin:${PATH}" \
    DISPLAY=:1 \
    PLAYWRIGHT_MCP_OUTPUT_DIR=/home/sandbox/.playwright-cli \
    PLAYWRIGHT_DAEMON_SESSION_DIR=/home/sandbox/.cache/ms-playwright/daemon
ENTRYPOINT ["/home/entrypoint.sh"]
