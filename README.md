# sandbox-desktop

## 问题与能力

需要一个**可本地构建、带图形桌面的 Linux 容器**：浏览器里看桌面（noVNC）、用带 CDP 的 Chrome 做自动化/调试，并可选把 Chrome 画面以 MJPEG 流出（可点击）。本镜像提供这些能力，身份为用户 `sandbox`（uid 1000），业务代码工作目录为 `/home/workspace`。

能力概览：

- 桌面：XFCE + TigerVNC + noVNC（HTTPS `:6080`，token 登录）
- 浏览器：`google-chrome-stable`，经 `chrome-cdp` 固定 CDP profile（`127.0.0.1:9222`，**不**映射到宿主机，无 socat）
- Chrome 画面：`chrome-cdp-view` MJPEG（`:9333`，需 token；可加 `click=1` 映射鼠标到 CDP）
- 运行时：Node 24、`playwright-cli`；轻量中文字体 `fonts-wqy-zenhei`
- 登录 token **仅**运行时环境变量 `NOVNC_TOKEN`、`CDP_VIEW_TOKEN`（镜像不内置默认/随机值；缺则入口报错退出）

## 目录介绍

| 路径 | 用途 |
|------|------|
| `Dockerfile` | 镜像构建定义（Debian trixie、桌面组件、Chrome、入口脚本安装） |
| `README.md` | 本说明：能力、目录、构建与运行 |
| `scripts/entrypoint.sh` | 容器入口：校验 token、拉起 VNC/XFCE、Chrome CDP、cdp-view 与 monitor |
| `scripts/chrome-cdp` | Chrome 启动包装：固定 CDP profile 与 `127.0.0.1:9222` |
| `scripts/chrome-cdp-view.mjs` | `:9333` MJPEG 流出 Chrome 画面；可选 `click` 映射鼠标到 CDP |
| `scripts/chrome-cdp-monitor.sh` | 周期探测 CDP；挂了则重启 Chrome 并 re-attach `playwright-cli` |
| `scripts/seed-chrome-cdp-appearance.py` | 启动前把外观相关偏好从普通 Chrome profile 同步到 CDP profile |
| `scripts/start-novnc.sh` | 辅助：起 VNC `:1` 与 websockify/noVNC `:6080` |
| `scripts/xstartup` | TigerVNC 会话脚本：`exec startxfce4` |
| `scripts/xfce-seed/` | XFCE 面板/默认浏览器/mime 等种子配置（Web Browser → `chrome-cdp`） |
| `vendor/` | 可选本地 Chrome `.deb`（网络拉包失败时放入，构建时优先使用；`*.deb` 已 gitignore） |
| `.gitignore` | 忽略日志、bak、`.env`、`vendor/*.deb` 等 |

容器内对应布局：入口 `/home/sandbox/project/entrypoint.sh`；可执行脚本在 `/home/sandbox/.local/bin/`；VNC 相关在 `/home/sandbox/.vnc/`；`WORKDIR=/home/workspace` 只放后续业务/仓库代码。

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

| 变量 | 必需 | 说明 |
|------|------|------|
| `NOVNC_TOKEN` | 是 | noVNC 登录 token；缺则 entrypoint 报错退出 |
| `CDP_VIEW_TOKEN` | 是 | chrome-cdp-view（9333）访问 token；缺则入口/服务报错退出 |
| `TZ` | 否 | 时区；镜像默认 `Asia/Shanghai`，可按需覆盖 |
| `HOME` | 否 | 镜像已设为 `/home/sandbox`，一般不用改 |
| `USER` | 否 | 镜像已设为 `sandbox`，一般不用改 |
| `DISPLAY` | 否 | 镜像已设为 `:1`，一般不用改 |
| `LANG` | 否 | 镜像已设为 `C.UTF-8`，一般不用改 |
| `PATH` | 否 | 镜像已设（含 `~/.local/bin` 与 Node 24），一般不用改 |

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
