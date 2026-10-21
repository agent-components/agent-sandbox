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
        procps iproute2 \
        xz-utils \
        openssh-client openssh-server \
        fonts-wqy-zenhei \
        scrot \
        xdotool \
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
    # Move install tree off /opt: child images (e.g. billion) bind-mount an empty /opt.
    mkdir -p /usr/local/google; \
    mv /opt/google/chrome /usr/local/google/chrome; \
    rmdir /opt/google 2>/dev/null || true; \
    # Replace package bin with .real symlink + no-sandbox wrapper.
    # rm first so printf does not follow a stale symlink into the chrome tree.
    rm -f /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable.real; \
    ln -sfn /usr/local/google/chrome/google-chrome /usr/bin/google-chrome-stable.real; \
    # Container/qemu need --no-sandbox; keep scripts/chrome-cdp identical to sandbox.
    printf '%s\n' '#!/bin/sh' 'exec /usr/bin/google-chrome-stable.real --no-sandbox --disable-gpu "$@"' \
      > /usr/bin/google-chrome-stable; \
    chmod 755 /usr/bin/google-chrome-stable; \
    # alternatives: google-chrome -> google-chrome-stable (wrapper); desktop Exec uses same.
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
# Runtime CDP profile is /opt/google-chrome-cdp (may be wiped by empty /opt mount).
# Default seed is baked later under /usr/local/share/google-chrome-cdp-seed.

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
COPY --chown=sandbox:sandbox scripts/entrypoint.sh /home/sandbox/project/entrypoint.sh
COPY --chown=sandbox:sandbox scripts/chrome-cdp /home/sandbox/.local/bin/chrome-cdp
COPY --chown=sandbox:sandbox scripts/seed-chrome-cdp-appearance.py /home/sandbox/.local/bin/seed-chrome-cdp-appearance.py
COPY --chown=sandbox:sandbox scripts/chrome-cdp-monitor.sh /home/sandbox/.local/bin/chrome-cdp-monitor.sh
COPY --chown=sandbox:sandbox scripts/chrome-cdp-view.mjs /home/sandbox/.local/bin/chrome-cdp-view.mjs
COPY --chown=sandbox:sandbox scripts/start-novnc.sh /home/sandbox/.local/bin/start-novnc.sh
# TigerVNC 1.15 (trixie) reads ~/.config/tigervnc; keep both paths.
COPY --chown=sandbox:sandbox scripts/xstartup /home/sandbox/.vnc/xstartup
COPY --chown=sandbox:sandbox scripts/xstartup /home/sandbox/.config/tigervnc/xstartup
# xfce-seed: panel/helpers point Web Browser -> ~/.local/bin/chrome-cdp (CDP profile)
COPY --chown=sandbox:sandbox scripts/xfce-seed/ /home/sandbox/.config/xfce-seed/
# Custom noVNC lite page (clipboard + hidden status bar); used by prepare_novnc_web.
COPY --chown=sandbox:sandbox scripts/novnc/vnc_lite.html /home/sandbox/.local/share/novnc/vnc_lite.html

RUN chmod 755 /home/sandbox/project/entrypoint.sh \
              /home/sandbox/.local/bin/chrome-cdp \
              /home/sandbox/.local/bin/seed-chrome-cdp-appearance.py \
              /home/sandbox/.local/bin/chrome-cdp-monitor.sh \
              /home/sandbox/.local/bin/chrome-cdp-view.mjs \
              /home/sandbox/.local/bin/start-novnc.sh \
              /home/sandbox/.vnc/xstartup \
              /home/sandbox/.config/tigervnc/xstartup

# Bake CDP profile seed outside /opt so child images that bind-mount an empty
# /opt still get classic theme + download prefs on first start (entrypoint clones
# into /opt/google-chrome-cdp only when that dir is empty / missing Preferences).
RUN set -eux; \
    mkdir -p /usr/local/share/google-chrome-cdp-seed; \
    HOME=/home/sandbox CHROME_CDP_USER_DATA_DIR=/usr/local/share/google-chrome-cdp-seed \
      python3 /home/sandbox/.local/bin/seed-chrome-cdp-appearance.py; \
    chown -R sandbox:sandbox /usr/local/share/google-chrome-cdp-seed; \
    test -f /usr/local/share/google-chrome-cdp-seed/Default/Preferences

EXPOSE 6080 9333

USER sandbox
WORKDIR /home/workspace
ENV PATH="/home/sandbox/.local/bin:/home/sandbox/.local/node-v24/bin:${PATH}"
ENTRYPOINT ["/home/sandbox/project/entrypoint.sh"]
