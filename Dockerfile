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
    sh /tmp/install-node.sh \
 && sh /tmp/install-desktop-apt.sh \
 && sh /tmp/install-chrome.sh

# sshd 配置（openssh-server 已由 install-desktop-apt 安装）
RUN sh /tmp/install-ssh.sh install

# agent-gateway 一键二进制 → /root/.local/bin。
# 不在镜像层创建 /data 下的目录：/data 是挂载卷，构建期目录会被盖住。
# 缓存、日志在 entrypoint 调用 start 时再建。
RUN sh /tmp/install-agent-gateway.sh install

EXPOSE 6080 9333 6090 22

WORKDIR /home/workspace
ENV PATH="/data/npm-global/bin:/root/.local/bin:/root/.local/node-v24/bin:${PATH}" \
    LANG=C.UTF-8 \
    DISPLAY=:1 \
    LOG_DIR=/data/log \
    npm_config_cache=/data/npm \
    npm_config_prefix=/data/npm-global \
    PLAYWRIGHT_MCP_OUTPUT_DIR=/data/.playwright-cli
ENTRYPOINT ["/home/entrypoint.sh"]
