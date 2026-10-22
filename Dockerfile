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
    && chown -R sandbox:sandbox /home/sandbox /home/workspace /opt/downloads /opt/google-chrome-cdp /opt/log

# All sources first
COPY --chmod=755 docker/tmp/ /tmp/
COPY --chown=sandbox:sandbox docker/home/ /home/
COPY docker/usr/local/share/google-chrome-cdp/ /usr/local/share/google-chrome-cdp/

# Then install in order
RUN /tmp/install-desktop-apt.sh
RUN /tmp/install-node.sh
RUN /tmp/install-chrome.sh

RUN chmod -R a+rX /home/sandbox/.local/bin \
 && chmod 755 /home/sandbox/.vnc/xstartup /home/sandbox/.config/tigervnc/xstartup \
 && chown -R sandbox:sandbox /home/sandbox /usr/local/share/google-chrome-cdp /opt/downloads /opt/log \
 && rm -rf /tmp/*

EXPOSE 6080 9333

USER sandbox
WORKDIR /home/workspace
ENV PATH="/home/sandbox/.local/bin:/home/sandbox/.local/node-v24/bin:${PATH}" \
    DISPLAY=:1
ENTRYPOINT ["/home/entrypoint.sh"]
