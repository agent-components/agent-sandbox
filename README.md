# sandbox-desktop 0.0.2（约 1.71GB）

## 问题与能力

本地可构建的 Linux 图形桌面容器。浏览器里看桌面，用 Chrome 做自动化和调试，也可以单独打开 Chrome 画面并点击操作。业务代码放在 `/home/workspace`。

- 桌面：浏览器直接打开，默认 `1920×1080`
- Chrome：容器内可远程调试，供自动化使用
- Chrome 画面：可单独查看，并可点击操作

## 目录介绍

| 路径                                          | 用途                                                                                            |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `docker/home/sandbox/`                        | 与容器 `/home/sandbox/` 同构；Dockerfile 一次 `COPY` 映射进去                                   |
| `docker/usr/local/share/google-chrome-cdp/`   | CDP 默认 Preferences → `/usr/local/share/google-chrome-cdp/`                                    |
| `docker/home/entrypoint.sh`                   | 入口编排 → `/home/entrypoint.sh`；调 `start_vnc.sh`，CDP 由 dock 按需启动                       |
| `docker/home/start/`                          | 可选运维脚本 → `/home/start/`（如 `install-cursor-cli.sh`）                                     |
| `docker/home/sandbox/.local/bin/start_vnc.sh` | 虚拟桌面启动（VNC / noVNC / dock 置底）                                                         |
| `docker/tmp/`                                 | 预取的 Chrome `.deb` / Node `.tar.xz`，以及构建安装脚本；构建时 bind 进同一个 RUN，不打进镜像层 |
| `scripts/download-chrome-dep.sh`              | 下载 Chrome `.deb` 到 `docker/tmp/`（不打进 git）                                               |
| `scripts/download-node-dep.sh`                | 下载 Node linux-x64 `.tar.xz` 到 `docker/tmp/`（不打进 git）                                    |
| `Dockerfile`                                  | 镜像构建                                                                                        |
| `README.md`                                   | 本说明                                                                                          |
| `AGENTS.md`                                   | 给 AI 看的容器能力说明：Node / Python、playwright-cli、桌面截图与键鼠                           |

容器内对应布局：入口 `/home/entrypoint.sh`；可执行脚本在 `/home/sandbox/.local/bin/`；VNC 相关在 `/home/sandbox/.vnc/`；`WORKDIR=/home/workspace` 只放后续业务/仓库代码。Chrome 二进制在 `/usr/local/google/chrome`；CDP 运行时 profile `/opt/google-chrome-cdp`；CDP 默认配置 `/usr/local/share/google-chrome-cdp`；下载目录 `/opt/downloads`。

## 构建

```bash
cd ~/docker-sandbox-desktop
# 若尚无依赖包，先预取（写入 docker/tmp/）：
./scripts/download-chrome-dep.sh
./scripts/download-node-dep.sh
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
  local/sandbox-desktop:0.1.0
```

## 环境变量

| 变量                     | 必需 | 说明                                                                                                                                       |
| ------------------------ | ---- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `NOVNC_TOKEN`            | 是   | noVNC 登录 token；缺则 entrypoint 报错退出                                                                                                 |
| `CDP_VIEW_TOKEN`         | 是   | chrome-cdp-view（9333）访问 token；缺则入口/服务报错退出                                                                                   |
| `SANDBOX_DISPLAY_WIDTH`  | 否   | 桌面 / Chrome 窗口宽度（像素）；默认 `1920`。entrypoint 传给 `vncserver -geometry`，`chrome-cdp` 用 `--window-size`；CDP viewport 与此一致 |
| `SANDBOX_DISPLAY_HEIGHT` | 否   | 桌面 / Chrome 窗口高度（像素）；默认 `1080`。同上                                                                                          |

## 端口

| 端口 | 用途                                  |
| ---- | ------------------------------------- |
| 6080 | noVNC HTTPS                           |
| 9333 | chrome-cdp-view MJPEG（需 `?token=`） |

## 访问

- 桌面：打开 [https://127.0.0.1:6080/vnc_lite.html?autoconnect=1&reconnect=1&resize=scale&path=websockify%3Ftoken%3Dlocal-novnc-token](https://127.0.0.1:6080/vnc_lite.html?autoconnect=1&reconnect=1&resize=scale&path=websockify%3Ftoken%3Dlocal-novnc-token) （自签证书需浏览器放行）。底部 dock（终端 / workspace / Chrome CDP）；无 Applications/时钟/用户顶栏。Chrome 仍由入口 `chrome-cdp` 自动拉起
- Chrome 画面：打开 [http://127.0.0.1:9333/?token=local-cdp-token&click=1](http://127.0.0.1:9333/?token=local-cdp-token&click=1)
