# sandbox-desktop 0.0.2（约 1.71GB）

## 问题与能力

本地可构建的 Linux 图形桌面容器。浏览器里看桌面，用 Chrome 做自动化和调试，也可以单独打开 Chrome 画面并点击操作。业务代码放在 `/home/workspace`。

- 桌面：浏览器直接打开，默认 `1920×1080`
- Chrome：容器内可远程调试，供自动化使用
- Chrome 画面：可单独查看，并可点击操作

## 目录介绍

| 路径                                          | 用途                                                                             |
| --------------------------------------------- | -------------------------------------------------------------------------------- |
| `docker/home/sandbox/`                        | 与容器 `/home/sandbox/` 同构；Dockerfile 一次 `COPY` 映射进去                    |
| `docker/usr/local/share/google-chrome-cdp/`   | CDP 默认 Preferences → `/usr/local/share/google-chrome-cdp/`                     |
| `docker/home/entrypoint.sh`                   | 入口编排 → `/home/entrypoint.sh`；调 `start_vnc.sh`，CDP 由 dock 按需启动        |
| `docker/home/start/`                          | 可选运维脚本 → `/home/start/`（如 `install-cursor-cli.sh`）                      |
| `docker/home/sandbox/.local/bin/start_vnc.sh` | 虚拟桌面启动（VNC / noVNC / dock 置底）                                          |
| `docker/tmp/`                                 | 预取的 Chrome `.deb` / Node `.tar.xz`，以及构建安装脚本（一次 `COPY` 到 `/tmp`） |
| `scripts/download-chrome-dep.sh`              | 下载 Chrome `.deb` 到 `docker/tmp/`（不打进 git）                                |
| `scripts/download-node-dep.sh`                | 下载 Node linux-x64 `.tar.xz` 到 `docker/tmp/`（不打进 git）                     |
| `Dockerfile`                                  | 镜像构建                                                                         |
| `README.md`                                   | 本说明                                                                           |
| `AGENTS.md`                                   | 给 AI 看的容器能力说明：Node / Python、playwright-cli、桌面截图与键鼠            |

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

## Agent 如何和这个沙箱交互

Agent 把本容器当作**可执行命令的远程桌面实例**：不直接映射 CDP 到宿主机，而是用 `docker exec` 进容器，在已有 XFCE / Chrome CDP / `playwright-cli` 会话上操作。业务代码工作目录为 `/home/workspace`；图形会话为 `DISPLAY=:1`；Chrome 远程调试仅监听容器内 `127.0.0.1:9222`（由 dock 的 `launch-chrome-cdp` 冷启动时带起，并 `playwright-cli attach`；关掉 Chrome 后 CDP 一并退出，不再用 monitor 定时拉起）。桌面与 Chrome 窗口分辨率由 `SANDBOX_DISPLAY_WIDTH` / `SANDBOX_DISPLAY_HEIGHT` 控制（默认 `1920`×`1080`）：`start_vnc.sh` 用其对 `vncserver -geometry`，`chrome-cdp` 用 `--window-position=0,0` 与 `--window-size=${W},${H}`，使 CDP viewport 与设定一致；`:9333` screencast 的 max 宽高也读同一组环境变量。公开端口仍是 **6080（noVNC）+ 9333（cdp-view）**；5901 / 9222 仅容器内环回。

以下示例容器名与上文「运行」一致：`sandbox-desktop-test`。

### 进入容器执行命令

```bash
# 交互 shell（用户 sandbox，WORKDIR 已是 /home/workspace）
docker exec -it sandbox-desktop-test bash

# 单条命令（非交互）
docker exec sandbox-desktop-test bash -lc 'pwd; echo DISPLAY=$DISPLAY'
# 期望：/home/workspace 与 :1
```

确认 CDP 存活（仅容器内环回）：

```bash
docker exec sandbox-desktop-test curl -s http://127.0.0.1:9222/json/version
```

### 用 playwright-cli 做浏览器自动化（CDP 9222）

镜像已装 `@playwright/cli`（命令 `playwright-cli`）。入口启动 Chrome 后会执行：

`playwright-cli attach --cdp=http://127.0.0.1:9222`

若会话断开或需重新挂上：

```bash
docker exec sandbox-desktop-test bash -lc '
  export PATH="/home/sandbox/.local/bin:$PATH"
  playwright-cli detach >/dev/null 2>&1 || true
  playwright-cli attach --cdp=http://127.0.0.1:9222
'
```

常用操作（均在容器内、已 attach 的前提下）：

```bash
docker exec sandbox-desktop-test bash -lc '
  export PATH="/home/sandbox/.local/bin:$PATH"
  playwright-cli goto https://example.com
  playwright-cli snapshot
  playwright-cli click e3          # e3 来自 snapshot 的 ref
  playwright-cli type "hello"
  playwright-cli press Enter
'
```

dock 与 MIME 默认浏览器都指向 `chrome-cdp`（同一 CDP profile / `:9222`），与 `playwright-cli` 操作的是同一 Chrome。

### 截图

#### 桌面截图（整屏 XFCE / `DISPLAY=:1`）

镜像已安装 `scrot`。截取整个桌面：

```bash
docker exec -e DISPLAY=:1 <容器> scrot /tmp/desktop.png
# 例：
docker exec -e DISPLAY=:1 sandbox-desktop-test scrot /tmp/desktop.png
# 拷到宿主机：
docker cp sandbox-desktop-test:/tmp/desktop.png ./desktop.png
```

也可继续用人眼/自动化走 noVNC（`:6080`）或 `chrome-cdp-view` MJPEG（`:9333`）看画面。

#### 桌面点击 / 键鼠（xdotool）

镜像已安装 `xdotool`。在 `DISPLAY=:1` 上模拟鼠标与键盘（整桌面，不经 CDP）：

```bash
# 移动并左键点击（坐标相对桌面）
docker exec -e DISPLAY=:1 <容器> xdotool mousemove 960 540 click 1
# 例（默认 1920x1080 中心；若改了 SANDBOX_DISPLAY_* 请按实际分辨率调整）：
docker exec -e DISPLAY=:1 sandbox-desktop-test xdotool mousemove 960 540 click 1

# 双击 / 右键
docker exec -e DISPLAY=:1 sandbox-desktop-test xdotool mousemove 200 120 click --repeat 2 1
docker exec -e DISPLAY=:1 sandbox-desktop-test xdotool mousemove 200 120 click 3

# 输入文字 / 按键
docker exec -e DISPLAY=:1 sandbox-desktop-test xdotool type 'hello'
docker exec -e DISPLAY=:1 sandbox-desktop-test xdotool key Return
docker exec -e DISPLAY=:1 sandbox-desktop-test xdotool key ctrl+l

# 查窗口并激活后点击（示例：按名称）
docker exec -e DISPLAY=:1 sandbox-desktop-test bash -lc '
  wid=$(xdotool search --name "Chrome" | head -1)
  [ -n "$wid" ] && xdotool windowactivate "$wid" mousemove --window "$wid" 100 100 click 1
'
```

浏览器页内精准点击仍优先 `playwright-cli click`（CDP）；整桌面/非 Chrome 窗口用 `xdotool`。

#### 浏览器页面截图（CDP / playwright-cli）

截取浏览器页面请用已安装的 `playwright-cli screenshot`（经 CDP，对应当前页或元素）：

```bash
docker exec sandbox-desktop-test bash -lc '
  export PATH="/home/sandbox/.local/bin:$PATH"
  # 当前视口 → 默认 page-{timestamp}.png
  playwright-cli screenshot
  # 指定文件与格式
  playwright-cli screenshot --filename=/home/workspace/shot.png
  playwright-cli screenshot --filename=/home/workspace/shot.jpeg --type=jpeg
  # 整页滚动截图 / 高分屏像素
  playwright-cli screenshot --full-page --filename=/home/workspace/full.png
  playwright-cli screenshot --hires --filename=/home/workspace/hires.png
  # 元素：先 snapshot 拿 ref，再截该元素
  playwright-cli screenshot e3 --filename=/home/workspace/el.png
'
```
