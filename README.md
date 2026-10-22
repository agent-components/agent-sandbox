# sandbox-desktop 0.0.2（约 1.71GB）

## 问题与能力

需要一个**可本地构建、带图形桌面的 Linux 容器**：浏览器里看桌面（noVNC）、用带 CDP 的 Chrome 做自动化/调试，并可选把 Chrome 画面以 MJPEG 流出（可点击）。本镜像提供这些能力，身份为用户 `sandbox`（uid 1000），业务代码工作目录为 `/home/workspace`。

能力概览：

- 桌面：XFCE + TigerVNC + noVNC（HTTPS `:6080`；WebSocket 需自行提供 token，静态页不嵌入）；分辨率由 `SANDBOX_DISPLAY_WIDTH`/`HEIGHT` 控制，默认 `1920x1080`
- 浏览器：`google-chrome-stable`（安装树在 `/usr/local/google/chrome`，避开子镜像对 `/opt` 的空盘挂载）；经 `chrome-cdp` 固定 CDP profile（`--user-data-dir=/opt/google-chrome-cdp`，`127.0.0.1:9222`，**不**映射到宿主机，无 socat）；构建期默认 profile 种子在 `/usr/local/share/google-chrome-cdp-seed`（不被 `/opt` 挂载盖住），entrypoint 仅在 `/opt/google-chrome-cdp` 为空或缺 `Default/Preferences` 时 `cp -a` 克隆过去；窗口用 `--window-size` 对齐上述分辨率，CDP viewport 同尺寸；默认下载目录 `/opt/downloads`
- Chrome 画面：`chrome-cdp-view` MJPEG（`:9333`，需 token；可加 `click=1` 映射鼠标到 CDP）
- 运行时：Node 24、`playwright-cli`；轻量中文字体 `fonts-wqy-zenhei`
- 登录 token **仅**运行时环境变量 `NOVNC_TOKEN`、`CDP_VIEW_TOKEN`（镜像不内置默认/随机值；缺则入口报错退出）

## 目录介绍

| 路径 | 用途 |
| ---- | ---- |
| `docker/home/sandbox/` | 与容器 `/home/sandbox/` 同构；Dockerfile 一次 `COPY` 映射进去 |
| `docker/usr/local/share/google-chrome-cdp-seed/` | CDP Preferences 种子 → `/usr/local/share/...` |
| `docker/home/sandbox/project/entrypoint.sh` | 入口编排：调 `start_vnc.sh` 再起 Chrome CDP |
| `docker/home/sandbox/.local/bin/start_vnc.sh` | 虚拟桌面启动（VNC / noVNC / dock 置底） |
| `vendor/` | 本地 Chrome `.deb` |
| `Dockerfile` | 镜像构建 |
| `README.md` | 本说明 |

容器内对应布局：入口 `/home/sandbox/project/entrypoint.sh`；可执行脚本在 `/home/sandbox/.local/bin/`；VNC 相关在 `/home/sandbox/.vnc/`；`WORKDIR=/home/workspace` 只放后续业务/仓库代码。Chrome 二进制在 `/usr/local/google/chrome`；CDP 运行时 profile `/opt/google-chrome-cdp`；CDP 构建种子 `/usr/local/share/google-chrome-cdp-seed`；下载目录 `/opt/downloads`。

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
  # 可选：-e SANDBOX_DISPLAY_WIDTH=1920 -e SANDBOX_DISPLAY_HEIGHT=1080 \
  local/sandbox-desktop:0.1.0
```

Apple Silicon 上 `linux/amd64` 经 QEMU 跑 Chrome 时，建议加 `--security-opt seccomp=unconfined`。镜像内对 `/usr/bin/google-chrome-stable` 做了薄包装（`--no-sandbox --disable-gpu`），`/usr/bin/google-chrome-stable.real` → `/usr/local/google/chrome/google-chrome`；`scripts/chrome-cdp` 仍为沙箱原文。Chrome 默认下载目录为 `/opt/downloads`，CDP `--user-data-dir` 为 `/opt/google-chrome-cdp`。构建期把 `scripts/chrome-cdp-seed/` 拷进 `/usr/local/share/google-chrome-cdp-seed`（不在 `/opt` 下，空盘挂载盖不掉）；entrypoint 启动时若 `/opt/google-chrome-cdp` 为空或缺 `Default/Preferences` 则 `cp -a` 种子过去，已有用户数据则跳过。子镜像若把空卷挂到 `/opt`，需在 root 入口里同样保证 `/opt/downloads` 与 `/opt/google-chrome-cdp` 可写。

运行时必须传入 `NOVNC_TOKEN` 与 `CDP_VIEW_TOKEN`。

## 环境变量

| 变量                     | 必需 | 说明                                                                                                                                       |
| ------------------------ | ---- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `NOVNC_TOKEN`            | 是   | noVNC 登录 token；缺则 entrypoint 报错退出                                                                                                 |
| `CDP_VIEW_TOKEN`         | 是   | chrome-cdp-view（9333）访问 token；缺则入口/服务报错退出                                                                                   |
| `SANDBOX_DISPLAY_WIDTH`  | 否   | 桌面 / Chrome 窗口宽度（像素）；默认 `1920`。entrypoint 传给 `vncserver -geometry`，`chrome-cdp` 用 `--window-size`；CDP viewport 与此一致 |
| `SANDBOX_DISPLAY_HEIGHT` | 否   | 桌面 / Chrome 窗口高度（像素）；默认 `1080`。同上                                                                                          |
| `TZ`                     | 否   | 时区；镜像默认 `Asia/Shanghai`，可按需覆盖                                                                                                 |
| `HOME`                   | 否   | 镜像已设为 `/home/sandbox`，一般不用改                                                                                                     |
| `USER`                   | 否   | 镜像已设为 `sandbox`，一般不用改                                                                                                           |
| `DISPLAY`                | 否   | 镜像已设为 `:1`，一般不用改                                                                                                                |
| `LANG`                   | 否   | 镜像已设为 `C.UTF-8`，一般不用改                                                                                                           |
| `PATH`                   | 否   | 镜像已设（含 `~/.local/bin` 与 Node 24），一般不用改                                                                                       |

## 端口

| 端口 | 用途                                                                                           |
| ---- | ---------------------------------------------------------------------------------------------- |
| 5901 | TigerVNC（**仅**容器内 `localhost`，entrypoint 以 `-localhost yes` 启动；不要 `-p 5901:5901`） |
| 6080 | noVNC HTTPS（根路径跳转 vnc_lite，**不**带 token；WebSocket 需自行填 token）                   |
| 9222 | Chrome CDP（**仅**容器内 `127.0.0.1`；默认不要 `-p` 映射到宿主机，公网更不要 `-p 9222:9222`）  |
| 9333 | chrome-cdp-view MJPEG（需 `?token=`）                                                          |

安全：5901 只在容器内环回监听，对外只暴露 **6080 + TokenFile token**（及可选的 9333）。9222 只供容器内进程（playwright-cli / cdp-view）使用。调试：

```bash
docker exec sandbox-desktop-test curl -s http://127.0.0.1:9222/json/version
```

## 访问

- 桌面: https://127.0.0.1:6080/（自签证书需浏览器放行）
  - 根路径会跳到 `vnc_lite.html`，**不会**在 URL/静态页里嵌入 `NOVNC_TOKEN`
  - 底部 dock（终端 / workspace / Chrome CDP）；无 Applications/时钟/用户顶栏。Chrome 仍由入口 `chrome-cdp` 自动拉起
  - **剪贴板**：桌面焦点下 Ctrl+V 或 Mac Command+V 会把浏览器剪贴板同步进远程桌面并粘贴（需浏览器剪贴板权限；Cmd+V 会转成远程 Ctrl+V）
  - 连接前在 noVNC Settings 把 **path** 设为：`websockify?token=你的NOVNC_TOKEN`，再 Connect
  - 或手动打开（自行替换 token）：
    `https://127.0.0.1:6080/vnc_lite.html?autoconnect=1&reconnect=1&resize=scale&path=websockify%3Ftoken%3Dlocal-novnc-token`
  - websockify 仍用 TokenFile 校验；未带正确 token 时 WebSocket 会失败
- Chrome 画面: http://127.0.0.1:9333/?token=local-cdp-token
- 可点击操作（映射到 CDP `Input.dispatchMouseEvent`）: 加 `&click=1` 或 `&interactive=1`
  例: http://127.0.0.1:9333/?token=local-cdp-token&click=1

## Agent 如何和这个沙箱交互

Agent 把本容器当作**可执行命令的远程桌面实例**：不直接映射 CDP 到宿主机，而是用 `docker exec` 进容器，在已有 XFCE / Chrome CDP / `playwright-cli` 会话上操作。业务代码工作目录为 `/home/workspace`；图形会话为 `DISPLAY=:1`；Chrome 远程调试仅监听容器内 `127.0.0.1:9222`（由 `chrome-cdp` 启动，entrypoint / monitor 会 `playwright-cli attach`）。桌面与 Chrome 窗口分辨率由 `SANDBOX_DISPLAY_WIDTH` / `SANDBOX_DISPLAY_HEIGHT` 控制（默认 `1920`×`1080`）：entrypoint 用其对 `vncserver -geometry`，`chrome-cdp` 用 `--window-position=0,0` 与 `--window-size=${W},${H}`（不再依赖仅 `--start-maximized`），使 CDP 看到的 viewport/window 与设定一致；`:9333` screencast 的 max 宽高也读同一组环境变量。外观 seed 只同步主题/书签栏等，不改窗口状态。公开端口仍是 **6080（noVNC）+ 9333（cdp-view）**；5901 / 9222 仅容器内环回。

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
