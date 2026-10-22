# Local desktop image aligned with boat sandbox layout, username sandbox (uid 1000).
# Build: docker build --platform linux/amd64 -t local/sandbox-desktop:0.1.0 .
FROM debian:trixie-slim

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    HOME=/home/sandbox \
    USER=sandbox \
    DISPLAY=:1 \
    TZ=Asia/Shanghai

# Apt resilience for flaky CN mirrors / large debs (e.g. libllvm19)
RUN printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\n' \
      > /etc/apt/apt.conf.d/80-retries

# Tsinghua mirrors (network; not a feature addition)
RUN set -eux; \
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
      sed -i 's|deb.debian.org|mirrors.tuna.tsinghua.edu.cn|g; s|security.debian.org|mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list.d/debian.sources; \
    fi; \
    if [ -f /etc/apt/sources.list ]; then \
      sed -i 's|deb.debian.org|mirrors.tuna.tsinghua.edu.cn|g; s|security.debian.org|mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list; \
    fi

# Desktop + VNC + utils + lightweight CJK (WenQuanYi; not full Noto CJK)
RUN set -eux; \
    apt-get update; \
    for i in 1 2 3 4 5; do \
      apt-get install -y --no-install-recommends \
        xfce4 xfce4-terminal thunar \
        tigervnc-standalone-server \
        novnc websockify \
        python3 openssl \
        curl ca-certificates gnupg \
        dbus-x11 x11-utils \
        procps psmisc iproute2 \
        xz-utils \
        fonts-wqy-zenhei \
        scrot \
        xdotool \
        wmctrl \
        tzdata \
      && break; \
      echo "apt install failed (try $i), retrying..."; \
      apt-get update; \
      sleep $((i * 5)); \
    done; \
    dpkg -l fonts-wqy-zenhei \
        tzdata >/dev/null; \
    rm -rf /var/lib/apt/lists/*

# google-chrome-stable (amd64). Host-prefetched .deb: apt http to dl.google.com flakes in CN.
COPY vendor/google-chrome-stable_current_amd64.deb /tmp/google-chrome-stable_current_amd64.deb
RUN set -eux; \
    if [ "$TARGETARCH" != "amd64" ]; then \
      echo "This image expects TARGETARCH=amd64 (google-chrome-stable). Rebuild with --platform linux/amd64." >&2; \
      exit 1; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/google-chrome-stable_current_amd64.deb; \
    rm -f /tmp/google-chrome-stable_current_amd64.deb; \
    rm -rf /var/lib/apt/lists/*; \
    google-chrome-stable --version; \
    mkdir -p /usr/local/google; \
    mv /opt/google/chrome /usr/local/google/chrome; \
    rmdir /opt/google 2>/dev/null || true; \
    rm -f /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable.real; \
    ln -sfn /usr/local/google/chrome/google-chrome /usr/bin/google-chrome-stable.real; \
    printf '%s\n' '#!/bin/sh' 'exec /usr/bin/google-chrome-stable.real --no-sandbox --disable-gpu "$@"' \
      > /usr/bin/google-chrome-stable; \
    chmod 755 /usr/bin/google-chrome-stable; \
    test -x /usr/local/google/chrome/google-chrome; \
    test -x /usr/bin/google-chrome-stable; \
    google-chrome-stable --version

# sandbox user uid 1000; WORKDIR tree /home/workspace (code only)
RUN useradd -m -u 1000 -s /bin/bash sandbox \
    && mkdir -p /home/sandbox/.vnc \
               /home/sandbox/.config/tigervnc \
               /home/sandbox/.local/bin \
               /home/sandbox/.config \
               /home/sandbox/project \
               /home/sandbox/Desktop \
               /home/workspace \
               /opt/downloads \
               /opt/google-chrome-cdp \
    && chown -R sandbox:sandbox /home/sandbox /home/workspace /opt/downloads /opt/google-chrome-cdp

# Node 24 under ~/.local/node-v24 + bin symlinks
USER sandbox
WORKDIR /home/sandbox
RUN set -eux; \
    NODE_VER=v24.22.0; \
    curl -fsSL "https://npmmirror.com/mirrors/node/${NODE_VER}/node-${NODE_VER}-linux-x64.tar.xz" \
      -o /tmp/node.tar.xz; \
    mkdir -p /home/sandbox/.local/node-v24; \
    tar -xJf /tmp/node.tar.xz -C /home/sandbox/.local/node-v24 --strip-components=1; \
    rm /tmp/node.tar.xz; \
    ln -sf /home/sandbox/.local/node-v24/bin/node /home/sandbox/.local/bin/node; \
    ln -sf /home/sandbox/.local/node-v24/bin/npm /home/sandbox/.local/bin/npm; \
    ln -sf /home/sandbox/.local/node-v24/bin/npx /home/sandbox/.local/bin/npx; \
    export PATH="/home/sandbox/.local/bin:$PATH"; \
    npm i -g @playwright/cli; \
    ln -sf /home/sandbox/.local/node-v24/bin/playwright-cli /home/sandbox/.local/bin/playwright-cli || true; \
    test -x /home/sandbox/.local/bin/playwright-cli \
      || test -x /home/sandbox/.local/node-v24/bin/playwright-cli; \
    node --version; npm --version; \
    command -v playwright-cli || ls -la /home/sandbox/.local/node-v24/bin/

USER root
# Repo paths mirror the container: docker/home/sandbox/... → /home/sandbox/...
COPY --chown=sandbox:sandbox docker/home/sandbox/ /home/sandbox/
COPY docker/usr/local/share/google-chrome-cdp-seed/ /usr/local/share/google-chrome-cdp-seed/

RUN chmod 755 \
      /home/sandbox/project/entrypoint.sh \
      /home/sandbox/.local/bin/start_vnc.sh \
      /home/sandbox/.local/bin/chrome-cdp \
      /home/sandbox/.local/bin/chrome-cdp-runtime.sh \
      /home/sandbox/.local/bin/chrome-cdp-monitor.sh \
      /home/sandbox/.local/bin/chrome-cdp-view.mjs \
      /home/sandbox/.local/bin/single-instance \
      /home/sandbox/.local/bin/panel-keep-below.sh \
      /home/sandbox/.local/bin/launch-chrome-cdp \
      /home/sandbox/.local/bin/launch-terminal \
      /home/sandbox/.local/bin/launch-workspace \
      /home/sandbox/.local/bin/install-cursor-cli.sh \
      /home/sandbox/.vnc/xstartup \
      /home/sandbox/.config/tigervnc/xstartup \
 && chmod 644 /home/sandbox/Desktop/workspace.desktop \
 && mkdir -p /opt/downloads \
 && chown -R sandbox:sandbox /home/sandbox /usr/local/share/google-chrome-cdp-seed /opt/downloads \
 && test -f /home/sandbox/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml \
 && test -f /usr/local/share/google-chrome-cdp-seed/Default/Preferences

EXPOSE 6080 9333

USER sandbox
WORKDIR /home/workspace
ENV PATH="/home/sandbox/.local/bin:/home/sandbox/.local/node-v24/bin:${PATH}"
ENTRYPOINT ["/home/sandbox/project/entrypoint.sh"]
