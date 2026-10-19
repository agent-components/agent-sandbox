# Local desktop image aligned with boat sandbox layout, username apm (uid 1000).
# Build: docker build --platform linux/amd64 -t local/sandbox-desktop:0.1.0 .
FROM debian:trixie-slim

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    HOME=/home/apm \
    USER=apm \
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
    # Container/qemu need --no-sandbox; keep scripts/chrome-cdp identical to sandbox.
    mv /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable.real; \
    printf '%s\n' '#!/bin/sh' 'exec /usr/bin/google-chrome-stable.real --no-sandbox --disable-gpu "$@"' \
      > /usr/bin/google-chrome-stable; \
    chmod 755 /usr/bin/google-chrome-stable

# apm user uid 1000; WORKDIR tree /home/workspace (code only)
RUN useradd -m -u 1000 -s /bin/bash apm \
    && mkdir -p /home/apm/.vnc \
               /home/apm/.config/tigervnc \
               /home/apm/.local/bin \
               /home/apm/.config \
               /home/apm/project \
               /home/apm/Desktop \
               /home/workspace \
    && chown -R apm:apm /home/apm /home/workspace

# Node 24 under ~/.local/node-v24 + bin symlinks
USER apm
WORKDIR /home/apm
RUN set -eux; \
    NODE_VER=v24.22.0; \
    curl -fsSL "https://npmmirror.com/mirrors/node/${NODE_VER}/node-${NODE_VER}-linux-x64.tar.xz" \
      -o /tmp/node.tar.xz; \
    mkdir -p /home/apm/.local/node-v24; \
    tar -xJf /tmp/node.tar.xz -C /home/apm/.local/node-v24 --strip-components=1; \
    rm /tmp/node.tar.xz; \
    ln -sf /home/apm/.local/node-v24/bin/node /home/apm/.local/bin/node; \
    ln -sf /home/apm/.local/node-v24/bin/npm /home/apm/.local/bin/npm; \
    ln -sf /home/apm/.local/node-v24/bin/npx /home/apm/.local/bin/npx; \
    export PATH="/home/apm/.local/bin:$PATH"; \
    npm i -g @playwright/cli; \
    ln -sf /home/apm/.local/node-v24/bin/playwright-cli /home/apm/.local/bin/playwright-cli || true; \
    test -x /home/apm/.local/bin/playwright-cli \
      || test -x /home/apm/.local/node-v24/bin/playwright-cli; \
    node --version; npm --version; \
    command -v playwright-cli || ls -la /home/apm/.local/node-v24/bin/

USER root
COPY --chown=apm:apm scripts/entrypoint.sh /home/apm/project/entrypoint.sh
COPY --chown=apm:apm scripts/chrome-cdp /home/apm/.local/bin/chrome-cdp
COPY --chown=apm:apm scripts/seed-chrome-cdp-appearance.py /home/apm/.local/bin/seed-chrome-cdp-appearance.py
COPY --chown=apm:apm scripts/chrome-cdp-monitor.sh /home/apm/.local/bin/chrome-cdp-monitor.sh
COPY --chown=apm:apm scripts/chrome-cdp-view.mjs /home/apm/.local/bin/chrome-cdp-view.mjs
COPY --chown=apm:apm scripts/start-novnc.sh /home/apm/.local/bin/start-novnc.sh
# TigerVNC 1.15 (trixie) reads ~/.config/tigervnc; keep both paths.
COPY --chown=apm:apm scripts/xstartup /home/apm/.vnc/xstartup
COPY --chown=apm:apm scripts/xstartup /home/apm/.config/tigervnc/xstartup
# xfce-seed: panel/helpers point Web Browser -> ~/.local/bin/chrome-cdp (CDP profile)
COPY --chown=apm:apm scripts/xfce-seed/ /home/apm/.config/xfce-seed/

RUN chmod 755 /home/apm/project/entrypoint.sh \
              /home/apm/.local/bin/chrome-cdp \
              /home/apm/.local/bin/seed-chrome-cdp-appearance.py \
              /home/apm/.local/bin/chrome-cdp-monitor.sh \
              /home/apm/.local/bin/chrome-cdp-view.mjs \
              /home/apm/.local/bin/start-novnc.sh \
              /home/apm/.vnc/xstartup \
              /home/apm/.config/tigervnc/xstartup

EXPOSE 6080 8080 9333

USER apm
WORKDIR /home/workspace
ENV PATH="/home/apm/.local/bin:/home/apm/.local/node-v24/bin:${PATH}"
ENTRYPOINT ["/home/apm/project/entrypoint.sh"]
