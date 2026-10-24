# sandbox-desktop 0.0.2（约 1.71GB）

## 问题与能力

本地可构建的 Linux 图形桌面容器。浏览器里看桌面，用 Chrome 做自动化和调试，也可以单独打开 Chrome 画面并点击操作。业务代码放在 `/home/workspace`。

- 桌面：浏览器直接打开，默认 `1920×1080`
- Chrome：容器内可远程调试，供自动化使用
- Chrome 画面：可单独查看，并可点击操作

## 目录介绍

| 路径                                          | 用途                                                                                                                      |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `docker/home/sandbox/`                        | 与容器 `/home/sandbox/` 同构；Dockerfile 一次 `COPY` 映射进去                                                             |
| `docker/usr/local/share/google-chrome-cdp/`   | CDP 默认 profile 种子 → `/usr/local/share/google-chrome-cdp/`（`Default/Preferences`、可选 `Default/Bookmarks`）          |
| `docker/home/entrypoint.sh`                   | 入口编排 → `/home/entrypoint.sh`；调 `start_vnc.sh`；Chrome/CDP 默认 dock 按需，或 `SANDBOX_AUTO_START_CHROME=1` 开机自启 |
| `docker/home/start/`                          | 可选运维脚本 → `/home/start/`（如 `install-cursor-cli.sh`）                                                               |
| `docker/home/sandbox/.local/bin/start_vnc.sh` | 虚拟桌面启动（VNC / noVNC / dock 置底）                                                                                   |
| `vendor/`                                     | 预取的 Chrome `.deb` / Node `.tar.xz`；构建时只读 bind 到 `/mnt/vendor`，不打进镜像层                                     |
| `docker/tmp/`                                 | 构建安装脚本；复制到容器 `/tmp` 后执行                                                                                    |
| `scripts/download-chrome-dep.sh`              | 下载 Chrome `.deb` 到 `vendor/`（不打进 git）                                                                             |
| `scripts/download-node-dep.sh`                | 下载 Node linux-x64 `.tar.xz` 到 `vendor/`（不打进 git）                                                                  |
| `Dockerfile`                                  | 镜像构建                                                                                                                  |
| `README.md`                                   | 本说明                                                                                                                    |
| `AGENTS.md`                                   | 给 AI 看的容器能力说明：Node / Python、playwright-cli、桌面截图与键鼠                                                     |

容器内对应布局：入口 `/home/entrypoint.sh`；可执行脚本在 `/home/sandbox/.local/bin/`；VNC 相关在 `/home/sandbox/.vnc/`；`WORKDIR=/home/workspace` 只放后续业务/仓库代码。Chrome 二进制在 `/usr/local/google/chrome`；CDP 运行时 profile `/opt/google-chrome-cdp`；CDP 默认配置 `/usr/local/share/google-chrome-cdp`；下载目录 `/opt/downloads`。

### 下游默认书签

空 `/opt/google-chrome-cdp` 会整树克隆默认目录；**持久化 `/opt` 后不会再整树克隆**。若默认树有 `Default/Bookmarks`，会在首次准备 profile 时写入一次，之后用 `.bookmarks-seeded` 标记，不再覆盖（视为用户可能已改）。书签栏是否显示由 `Default/Preferences` 的 `bookmark_bar.show_on_all_tabs` 控制（随 Preferences 首次克隆）。

下游镜像 `COPY` 或启动时挂载即可：

```bash
-v "$PWD/Bookmarks:/usr/local/share/google-chrome-cdp/Default/Bookmarks:ro"
```

`Bookmarks` 为 Chrome 原生 JSON（含 `roots.bookmark_bar` 等）。要重新应用默认书签，需删掉运行时的 `.bookmarks-seeded`（或清空整个 `/opt/google-chrome-cdp`）。

## 构建

```bash
cd ~/docker-sandbox-desktop
# 若尚无依赖包，先预取（写入 vendor/）：
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

| 变量                        | 必需 | 说明                                                                                                                                       |
| --------------------------- | ---- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `NOVNC_TOKEN`               | 是   | noVNC 登录 token；缺则 entrypoint 报错退出                                                                                                 |
| `CDP_VIEW_TOKEN`            | 是   | chrome-cdp-view（9333）访问 token；缺则入口/服务报错退出                                                                                   |
| `SANDBOX_AUTO_START_CHROME` | 否   | `1` 开机自动执行 `launch-chrome-cdp`；`0` 或未设置则不自动启动，由 dock 按需打开                                                           |
| `SANDBOX_DISPLAY_WIDTH`     | 否   | 桌面 / Chrome 窗口宽度（像素）；默认 `1920`。entrypoint 传给 `vncserver -geometry`，`chrome-cdp` 用 `--window-size`；CDP viewport 与此一致 |
| `SANDBOX_DISPLAY_HEIGHT`    | 否   | 桌面 / Chrome 窗口高度（像素）；默认 `1080`。同上                                                                                          |

## 端口

| 端口 | 用途                                  |
| ---- | ------------------------------------- |
| 6080 | noVNC HTTPS                           |
| 9333 | chrome-cdp-view MJPEG（需 `?token=`） |

## 访问

- 桌面：打开 [https://127.0.0.1:6080/vnc_lite.html?autoconnect=1&reconnect=1&resize=scale&path=websockify%3Ftoken%3Dlocal-novnc-token](https://127.0.0.1:6080/vnc_lite.html?autoconnect=1&reconnect=1&resize=scale&path=websockify%3Ftoken%3Dlocal-novnc-token) （自签证书需浏览器放行）。底部 dock（终端 / workspace / Chrome CDP）；无 Applications/时钟/用户顶栏。`SANDBOX_AUTO_START_CHROME=1` 开机自启 Chrome，否则仅 dock 按需打开
- Chrome 画面：打开 [http://127.0.0.1:9333/?token=local-cdp-token&click=1](http://127.0.0.1:9333/?token=local-cdp-token&click=1)
