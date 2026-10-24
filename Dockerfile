# syntax=docker/dockerfile:1
# Local desktop image aligned with boat sandbox layout, username sandbox (uid 1000).
# Build: docker build --platform linux/amd64 -t local/sandbox-desktop:0.1.0 .
FROM debian:trixie-slim

ARG TARGETARCH
ENV HOME=/home/sandbox \
    USER=sandbox

# sandbox user uid 1000; WORKDIR tree /home/workspace (code only)
RUN useradd -m -u 1000 -s /bin/bash sandbox \
    && mkdir -p /home/workspace \
               /opt/downloads \
               /opt/google-chrome-cdp \
               /opt/log \
               /opt/npm/cache \
               /opt/playwright-cli/daemon \
    && chown -R sandbox:sandbox /home/sandbox /home/workspace /opt/downloads /opt/google-chrome-cdp /opt/log /opt/npm /opt/playwright-cli

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
 && chown -R sandbox:sandbox /home/sandbox /usr/local/share/google-chrome-cdp /opt/downloads /opt/log /opt/npm /opt/playwright-cli

EXPOSE 6080 9333

USER sandbox
WORKDIR /home/workspace
ENV PATH="/home/sandbox/.local/bin:/home/sandbox/.local/node-v24/bin:/opt/npm/bin:${PATH}" \
    DISPLAY=:1 \
    PLAYWRIGHT_MCP_OUTPUT_DIR=/opt/playwright-cli \
    PLAYWRIGHT_DAEMON_SESSION_DIR=/opt/playwright-cli/daemon
ENTRYPOINT ["/home/entrypoint.sh"]
