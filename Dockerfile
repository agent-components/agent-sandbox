# Local desktop image aligned with boat sandbox layout, username sandbox (uid 1000).
# Build: docker build --platform linux/amd64 -t local/sandbox-desktop:0.1.0 .
FROM debian:trixie-slim

ARG TARGETARCH
ENV HOME=/home/sandbox \
    USER=sandbox

COPY docker/build/install-desktop-apt.sh /tmp/install-desktop-apt.sh
RUN chmod +x /tmp/install-desktop-apt.sh && /tmp/install-desktop-apt.sh && rm -f /tmp/install-desktop-apt.sh

# google-chrome-stable (amd64). Host-prefetched .deb: apt http to dl.google.com flakes in CN.
# Prefetch: ./scripts/download-chrome-dep.sh → docker/home/sandbox/packages/
COPY docker/home/sandbox/packages/google-chrome-stable_current_amd64.deb /tmp/google-chrome-stable_current_amd64.deb
RUN set -eux; \
    if [ "$TARGETARCH" != "amd64" ]; then \
      echo "This image expects TARGETARCH=amd64 (google-chrome-stable). Rebuild with --platform linux/amd64." >&2; \
      exit 1; \
    fi; \
    export DEBIAN_FRONTEND=noninteractive; \
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
# Repo paths mirror the container: docker/home/... → /home/...
COPY --chown=sandbox:sandbox docker/home/sandbox/ /home/sandbox/
COPY --chmod=755 docker/home/entrypoint.sh /home/entrypoint.sh
COPY --chmod=755 docker/home/start/ /home/start/
COPY docker/usr/local/share/google-chrome-cdp/ /usr/local/share/google-chrome-cdp/

# Build-only Chrome .deb must not remain under /home/sandbox/packages
RUN rm -rf /home/sandbox/packages \
 && chmod -R a+rX /home/sandbox/.local/bin \
 && chmod 755 /home/sandbox/.vnc/xstartup /home/sandbox/.config/tigervnc/xstartup \
 && mkdir -p /opt/downloads \
 && chown -R sandbox:sandbox /home/sandbox /usr/local/share/google-chrome-cdp /opt/downloads

EXPOSE 6080 9333

USER sandbox
WORKDIR /home/workspace
ENV PATH="/home/sandbox/.local/bin:/home/sandbox/.local/node-v24/bin:${PATH}"
ENTRYPOINT ["/home/entrypoint.sh"]
