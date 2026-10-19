# local/sandbox-desktop:0.1.0

本地桌面镜像（对齐 boat 沙箱能力布局）。可见身份为 **sandbox**，工作目录 **WORKDIR=/home/workspace**。

- OS: Debian trixie；用户 `sandbox`（uid 1000，home `/home/sandbox`）
- **WORKDIR `/home/workspace`**：仅给后续 git 仓库代码，不放脚本/配置
- 脚本布局:
  - `/home/sandbox/project/entrypoint.sh`
  - `/home/sandbox/.local/bin/{chrome-cdp,chrome-cdp-view.mjs,start-novnc.sh,node,…}`
  - `/home/sandbox/.vnc/xstartup`（并写入 `~/.config/tigervnc/xstartup`，本地 trixie TigerVNC 1.15）
- 桌面: XFCE + TigerVNC + noVNC + websockify + google-chrome-stable
- 轻量 CJK: `fonts-wqy-zenhei`（无完整 fonts-noto-cjk）
- **无** socat（CDP 仅绑 `127.0.0.1:9222`）
- Node 24 在 `~/.local/node-v24`；`playwright-cli` 已装
- 面板 directorymenu / 文件快捷默认打开 `/home/workspace`；VNC desktop 名固定为 `Desktop`
- XFCE 默认 Web Browser / 面板浏览器 launcher 指向 `/home/sandbox/.local/bin/chrome-cdp`（`--user-data-dir=~/.config/google-chrome-cdp`，`--remote-debugging-port=9222`），避免再开默认 profile
- CDP profile 外观对齐 `~/.config/google-chrome`：启动前同步 Preferences 中主题/侧栏等外观键；首次可从正常 profile 复制非会话 Preferences/Local State。面板与默认浏览器仍走 chrome-cdp（可点 CDP）
- **登录 token 仅运行时环境变量**：`NOVNC_TOKEN`、`CDP_VIEW_TOKEN`（镜像不内置默认/随机 token；缺则入口报错退出）

## 构建

```bash
cd ~/docker-sandbox-desktop
# 若 apt 拉不到 Chrome，可先：
#   mkdir -p vendor && curl -fL -o vendor/google-chrome-stable_current_amd64.deb \
#     https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
docker build --platform linux/amd64 -t local/sandbox-desktop:0.1.0 .
```

## 运行

```bash
docker rm -f sandbox-desktop-test 2>/dev/null
docker run -d --name sandbox-desktop-test --hostname desktop --shm-size=1g -m 2g \
  --security-opt seccomp=unconfined \
  -p 6080:6080 -p 9333:9333 \
  -e NOVNC_TOKEN=local-novnc-token \
  -e CDP_VIEW_TOKEN=local-cdp-token \
  -e TZ=Asia/Shanghai \
  local/sandbox-desktop:0.1.0
```

Apple Silicon 上 `linux/amd64` 经 QEMU 跑 Chrome 时，建议加 `--security-opt seccomp=unconfined`。镜像内对 `/usr/bin/google-chrome-stable` 做了薄包装（`--no-sandbox --disable-gpu`），`scripts/chrome-cdp` 仍为沙箱原文。

运行时必须传入 `NOVNC_TOKEN` 与 `CDP_VIEW_TOKEN`。

## 环境变量

运行时由 `docker run -e` 传入；镜像**不**内置默认/随机登录 token。

| 变量 | 必需 | 说明 |
|------|------|------|
| `NOVNC_TOKEN` | 是 | noVNC 登录 token；缺则 entrypoint 报错退出 |
| `CDP_VIEW_TOKEN` | 是 | chrome-cdp-view（9333）访问 token；缺则入口/服务报错退出 |
| `TZ` | 否 | 时区；镜像默认 `Asia/Shanghai`，可按需覆盖 |

镜像内已设、一般无需改的变量：`HOME=/home/sandbox`、`USER=sandbox`、`DISPLAY=:1`、`LANG=C.UTF-8`，以及 `PATH`（含 `~/.local/bin` 与 Node 24）。

## 端口

| 端口 | 用途 |
|------|------|
| 6080 | noVNC HTTPS（根路径带 token 跳转） |
| 9333 | chrome-cdp-view MJPEG（需 `?token=`） |

CDP 不映射到宿主机。调试：

```bash
docker exec sandbox-desktop-test curl -s http://127.0.0.1:9222/json/version
```

## 访问

- 桌面: https://127.0.0.1:6080/（自签证书需浏览器放行）
- Chrome 画面: http://127.0.0.1:9333/?token=local-cdp-token
- 可点击操作（映射到 CDP `Input.dispatchMouseEvent`）: 加 `&click=1` 或 `&interactive=1`
  例: http://127.0.0.1:9333/?token=local-cdp-token&click=1

## 日志

以下假设容器名为 `sandbox-desktop-test`（与上文「运行」一致）。

查看容器标准输出/错误（entrypoint 主日志）：

```bash
docker logs sandbox-desktop-test
docker logs -f sandbox-desktop-test                 # 持续跟进
docker logs --tail 100 sandbox-desktop-test         # 最近 100 行
docker logs -f --tail 200 sandbox-desktop-test      # 跟进且先看最近 200 行
```

容器内自有日志（entrypoint 将后台进程输出重定向到文件）：

```bash
# Chrome CDP（含 monitor 重启时的追加输出）
docker exec sandbox-desktop-test cat /home/sandbox/.config/chrome-cdp.log
# chrome-cdp-view（9333）
docker exec sandbox-desktop-test cat /home/sandbox/.config/cdp-view.log
# noVNC / websockify（端口 6080）
docker exec sandbox-desktop-test cat /home/sandbox/.vnc/novnc-6080.log
```
