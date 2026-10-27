FROM debian:trixie-slim

RUN mkdir -p /home/workspace

COPY docker/root/ /root/
COPY docker/home/ /home/
COPY docker/usr/local/share/google-chrome-cdp/ /usr/local/share/google-chrome-cdp/
COPY docker/etc/xdg/xfce4/kiosk/ /etc/xdg/xfce4/kiosk/
COPY docker/tmp/ /tmp/

# Bind prefetched Chrome/Node from vendor (not image layers), then run the install scripts in /tmp.
RUN --mount=type=bind,source=vendor,target=/mnt/vendor,ro \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    chmod 755 /tmp/use-debian-mirror.sh /tmp/install-*.sh \
 && /tmp/install-desktop-apt.sh \
 && /tmp/install-node.sh \
 && /tmp/install-chrome.sh

EXPOSE 6080 9333

WORKDIR /home/workspace
ENV PATH="/root/.local/bin:/root/.local/node-v24/bin:${PATH}" \
    DISPLAY=:1 \
    PLAYWRIGHT_MCP_OUTPUT_DIR=/data/.playwright-cli \
    PLAYWRIGHT_DAEMON_SESSION_DIR=/data/.cache/ms-playwright/daemon
ENTRYPOINT ["/home/entrypoint.sh"]
