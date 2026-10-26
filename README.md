# agent-sandbox 0.0.1（约 529.951 MB）

Linux 图形桌面容器：浏览器看桌面、Chrome 远程调试、单独查看并可点击 Chrome 画面。工作目录为 `/home/workspace`。

让 AI 协助操作前，请先让它阅读 [`AGENTS.md`](./AGENTS.md)（容器内语言、浏览器、终端、截图与键鼠约定）。

- **桌面**：浏览器打开 noVNC，默认 `1920×1080`
- **Chrome**：容器内 CDP `127.0.0.1:9222`，供自动化
- **Chrome 画面**：9333 端口单独查看，可点击操作

## 快速开始（公开镜像）

镜像地址：`registry.cn-hangzhou.aliyuncs.com/agent-components/agent-sandbox:0.0.1`（公开拉取一般无需登录）。

```bash
docker pull registry.cn-hangzhou.aliyuncs.com/agent-components/agent-sandbox:0.0.1

docker rm -f agent-sandbox-test 2>/dev/null
docker run -d --name agent-sandbox-test --hostname desktop --shm-size=1g -m 2g \
  --security-opt seccomp=unconfined \
  -p 6080:6080 -p 9333:9333 \
  -v agent-sandbox-opt:/opt \
  -e NOVNC_TOKEN=local-novnc-token \
  -e CDP_VIEW_TOKEN=local-cdp-token \
  registry.cn-hangzhou.aliyuncs.com/agent-components/agent-sandbox:0.0.1
```

`-v agent-sandbox-opt:/opt` 把整盘 `/opt` 挂成卷，容器删掉后 Chrome 配置、下载等仍在（见「持久化 `/opt`」）。

可选：再挂自备书签（见「默认书签」）：

```bash
  -v "$PWD/Bookmarks:/usr/local/share/google-chrome-cdp/Default/Bookmarks:ro" \
```

## 访问

| 入口 | 地址 |
| ---- | ---- |
| 桌面（noVNC） | [https://127.0.0.1:6080/vnc_lite.html?autoconnect=1&reconnect=1&resize=scale&path=websockify%3Ftoken%3Dlocal-novnc-token](https://127.0.0.1:6080/vnc_lite.html?autoconnect=1&reconnect=1&resize=scale&path=websockify%3Ftoken%3Dlocal-novnc-token) |
| Chrome 画面 | [http://127.0.0.1:9333/?token=local-cdp-token&click=1](http://127.0.0.1:9333/?token=local-cdp-token&click=1) |

- noVNC 为自签证书，浏览器需放行。
- 默认不自动开 Chrome；设 `SANDBOX_AUTO_START_CHROME=1` 可开机自启。

## 端口

| 端口 | 用途 |
| ---- | ---- |
| 6080 | noVNC HTTPS |
| 9333 | chrome-cdp-view MJPEG（需 `?token=`） |

## 环境变量

| 变量 | 必需 | 说明 |
| ---- | ---- | ---- |
| `NOVNC_TOKEN` | 是 | noVNC 登录 token；缺则退出 |
| `CDP_VIEW_TOKEN` | 是 | chrome-cdp-view（9333）访问 token；缺则退出 |
| `SANDBOX_AUTO_START_CHROME` | 否 | `1` 开机执行 `launch-chrome-cdp`；默认不自动启动 |
| `SANDBOX_DISPLAY_WIDTH` | 否 | 桌面 / Chrome 宽度，默认 `1920` |
| `SANDBOX_DISPLAY_HEIGHT` | 否 | 桌面 / Chrome 高度，默认 `1080` |

## 持久化 `/opt`

需要保留的数据放在 `/opt` 下，并把整个 `/opt` 挂到卷或宿主机目录，这样换镜像、删容器也不会丢：

| 路径 | 内容 |
| ---- | ---- |
| `/opt/google-chrome-cdp` | Chrome / CDP 用户数据（书签、登录态等） |
| `/opt/downloads` | 浏览器下载、截图等 |
| `/opt/log` | noVNC / CDP / Chrome 等运行日志 |
| `/opt/npm` | npm 全局包与 cache（`cache/`） |
| `/opt/playwright-cli` | Playwright CLI 输出与 daemon 会话 |
| `/opt/cursor` | 可选：装 Cursor CLI 后落在这里（`install-cursor-cli.sh`） |

```bash
# Docker 命名卷（推荐）
-v agent-sandbox-opt:/opt

# 或绑到宿主机目录
-v "$PWD/opt-data:/opt"
```

工作目录 `/home/workspace` 不在 `/opt` 内；要一并保留请另挂 `-v ...:/home/workspace`。

## 默认书签

下游镜像可 `COPY`，或启动时挂载：

```bash
-v "$PWD/Bookmarks:/usr/local/share/google-chrome-cdp/Default/Bookmarks:ro"
```

要重新应用默认书签：清空 `/opt/google-chrome-cdp`。

`Bookmarks` 为 Chrome 原生 JSON。示例：

```json
{
  "roots": {
    "bookmark_bar": {
      "children": [
        {
          "name": "示例站点",
          "type": "url",
          "url": "https://example.com"
        },
        {
          "name": "文档",
          "type": "folder",
          "children": [
            {
              "name": "MDN",
              "type": "url",
              "url": "https://developer.mozilla.org"
            }
          ]
        }
      ],
      "name": "书签栏",
      "type": "folder"
    },
    "other": {
      "children": [],
      "name": "其他书签",
      "type": "folder"
    },
    "synced": {
      "children": [],
      "name": "移动设备书签",
      "type": "folder"
    }
  },
  "version": 1
}
```

## 本地构建

```bash
git clone https://github.com/agent-components/agent-sandbox.git
cd agent-sandbox

# 若尚无依赖包，先预取到 vendor/（不进 git）：
./scripts/download-chrome-dep.sh
./scripts/download-node-dep.sh

docker build --platform linux/amd64 -t local/agent-sandbox:0.0.1 .
```

运行方式与公开镜像相同，把镜像名换成 `local/agent-sandbox:0.0.1` 即可。

## 仓库目录

| 路径 | 用途 |
| ---- | ---- |
| `docker/home/sandbox/` | → 容器 `/home/sandbox/` |
| `docker/home/entrypoint.sh` | → `/home/entrypoint.sh`（调 `start_vnc.sh`；Chrome 按需或自启） |
| `docker/home/start/` | → `/home/start/`（如 `install-cursor-cli.sh`） |
| `docker/home/sandbox/.local/bin/start_vnc.sh` | VNC / noVNC / dock |
| `docker/usr/local/share/google-chrome-cdp/` | CDP profile 种子（`Preferences`、可选 `Bookmarks`） |
| `docker/tmp/` | 构建安装脚本 |
| `vendor/` | 预取的 Chrome / Node 包；构建时 bind，不进镜像层 |
| `scripts/download-chrome-dep.sh` | 下载 Chrome `.deb` |
| `scripts/download-node-dep.sh` | 下载 Node linux-x64 |
| `Dockerfile` | 镜像构建 |
| `AGENTS.md` | 给 AI 的容器能力说明 |
