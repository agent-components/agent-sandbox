# syntax=docker/dockerfile:1
# Local desktop image aligned with boat sandbox layout, username sandbox (uid 1000).
# Build: docker build --platform linux/amd64 -t local/sandbox-desktop:0.1.0 .
FROM debian:trixie-slim

ARG TARGETARCH
ARG NODE_VER=v24.22.0
ENV HOME=/home/sandbox \
    USER=sandbox

# sandbox user uid 1000; WORKDIR tree /home/workspace (code only)
RUN useradd -m -u 1000 -s /bin/bash sandbox \
    && mkdir -p /home/workspace \
               /opt/downloads \
               /opt/google-chrome-cdp \
               /opt/log \
    && chown -R sandbox:sandbox /home/sandbox /home/workspace /opt/downloads /opt/google-chrome-cdp /opt/log

COPY --chown=sandbox:sandbox docker/home/ /home/
COPY docker/usr/local/share/google-chrome-cdp/ /usr/local/share/google-chrome-cdp/

# One RUN: bind prefetched Chrome/Node (not image layers), cache apt/npm, install, then wipe /tmp.
RUN --mount=type=bind,source=docker/tmp,target=/mnt/build-tmp,ro \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/root/.npm,sharing=locked \
    cp /mnt/build-tmp/use-debian-mirror.sh \
       /mnt/build-tmp/install-desktop-apt.sh \
       /mnt/build-tmp/install-node.sh \
       /mnt/build-tmp/install-chrome.sh \
       /mnt/build-tmp/node-${NODE_VER}-linux-x64.tar.xz \
       /mnt/build-tmp/google-chrome-stable_current_amd64.deb \
       /tmp/ \
 && chmod 755 /tmp/use-debian-mirror.sh /tmp/install-*.sh \
 && /tmp/install-desktop-apt.sh \
 && NODE_VER="${NODE_VER}" /tmp/install-node.sh \
 && /tmp/install-chrome.sh \
 && chmod -R a+rX /home/sandbox/.local/bin \
 && chmod 755 /home/sandbox/.vnc/xstartup /home/sandbox/.config/tigervnc/xstartup \
 && chown -R sandbox:sandbox /home/sandbox /usr/local/share/google-chrome-cdp /opt/downloads /opt/log \
 && rm -rf /tmp/*

EXPOSE 6080 9333

USER sandbox
WORKDIR /home/workspace
ENV PATH="/home/sandbox/.local/bin:/home/sandbox/.local/node-v24/bin:${PATH}" \
    DISPLAY=:1
ENTRYPOINT ["/home/entrypoint.sh"]
