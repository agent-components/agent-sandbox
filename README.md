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
  -v agent-sandbox-data:/data \
  -e NOVNC_TOKEN=local-novnc-token \
  -e CDP_VIEW_TOKEN=local-cdp-token \
  registry.cn-hangzhou.aliyuncs.com/agent-components/agent-sandbox:0.0.1
```

`-v agent-sandbox-data:/data` 把整盘 `/data` 挂成卷，容器删掉后 Chrome 配置、下载等仍在（见「持久化 `/data`」）。

可选：再挂自备书签（见「默认书签」）：

```bash
  -v "$PWD/Bookmarks:/usr/local/share/google-chrome-cdp/Default/Bookmarks:ro" \
```

## 访问

| 入口          | 地址                                                                                                                                                                                                                                               |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 桌面（noVNC） | [https://127.0.0.1:6080/vnc_lite.html?autoconnect=1&reconnect=1&resize=scale&path=websockify%3Ftoken%3Dlocal-novnc-token](https://127.0.0.1:6080/vnc_lite.html?autoconnect=1&reconnect=1&resize=scale&path=websockify%3Ftoken%3Dlocal-novnc-token) |
| Chrome 画面   | [http://127.0.0.1:9333/?token=local-cdp-token&click=1](http://127.0.0.1:9333/?token=local-cdp-token&click=1)                                                                                                                                       |

- noVNC 为自签证书，浏览器需放行。
- 默认不自动开 Chrome；设 `SANDBOX_AUTO_START_CHROME=1` 可开机自启。

## 端口

| 端口 | 用途                                  |
| ---- | ------------------------------------- |
| 6080 | noVNC HTTPS                           |
| 9333 | chrome-cdp-view MJPEG（需 `?token=`） |

## 环境变量

| 变量                            | 必需 | 说明                                                             |
| ------------------------------- | ---- | ---------------------------------------------------------------- |
| `NOVNC_TOKEN`                   | 是   | noVNC 登录 token；缺则退出                                       |
| `CDP_VIEW_TOKEN`                | 是   | chrome-cdp-view（9333）访问 token；缺则退出                      |
| `SANDBOX_AUTO_START_CHROME`     | 否   | `1` 开机执行 `launch-chrome-cdp`；默认不自动启动                 |
| `SANDBOX_DISPLAY_WIDTH`         | 否   | 桌面 / Chrome 宽度，默认 `1920`                                  |
| `SANDBOX_DISPLAY_HEIGHT`        | 否   | 桌面 / Chrome 高度，默认 `1080`                                  |
| `LOG_DIR`                       | 否   | 日志目录，默认 `/data/log`                                       |
| `npm_config_cache`              | 否   | npm cache，默认 `/data/npm`                                      |
| `npm_config_prefix`             | 否   | `npm i -g` 前缀，默认 `/data/npm-global`                         |
| `PLAYWRIGHT_MCP_OUTPUT_DIR`     | 否   | Playwright 产物目录，默认 `/data/.playwright-cli`                |
| `PLAYWRIGHT_DAEMON_SESSION_DIR` | 否   | Playwright daemon 目录，默认 `/data/.cache/ms-playwright/daemon` |

## 持久化 `/data`

需要保留的数据放在 `/data` 下，并把整个 `/data` 挂到卷或宿主机目录，这样换镜像、删容器也不会丢：

| 路径                                | 内容                                                 |
| ----------------------------------- | ---------------------------------------------------- |
| `/data/google-chrome`               | Chrome CDP `user-data-dir`（配置、书签等）           |
| `/data/chrome-cache`                | Chrome `--disk-cache-dir`                            |
| `/data/downloads`                   | Chrome 下载目录；截图等也可写这里                    |
| `/data/log`                         | noVNC / CDP / Chrome 日志（可用 `LOG_DIR` 改）       |
| `/data/npm`                         | npm cache（`npm_config_cache`）                      |
| `/data/npm-global`                  | 全局 npm 包（`npm_config_prefix`）                   |
| `/data/.playwright-cli`             | Playwright 产物（`PLAYWRIGHT_MCP_OUTPUT_DIR`）       |
| `/data/.cache/ms-playwright/daemon` | Playwright daemon（`PLAYWRIGHT_DAEMON_SESSION_DIR`） |
| `/data/cursor`                      | 可选：跑 `install-cursor-cli.sh` 后写入（含 env.sh） |

```bash
# Docker 命名卷（推荐）
-v agent-sandbox-data:/data

# 或绑到宿主机目录
-v "$PWD/data:/data"
```

工作目录 `/home/workspace` 不在 `/data` 内；要一并保留请另挂 `-v ...:/home/workspace`。

## 默认书签

下游镜像可 `COPY`，或启动时挂载：

```bash
-v "$PWD/Bookmarks:/usr/local/share/google-chrome-cdp/Default/Bookmarks:ro"
```

要重新应用默认书签：清空 `/data/google-chrome`。

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

| 路径                                        | 用途                                                            |
| ------------------------------------------- | --------------------------------------------------------------- |
| `docker/root/`                              | → 容器 `/root/`（root 家目录）                                  |
| `docker/home/entrypoint.sh`                 | → `/home/entrypoint.sh`（调 `start_vnc.sh`；Chrome 按需或自启） |
| `docker/home/start/`                        | → `/home/start/`（如 `install-cursor-cli.sh`）                  |
| `docker/root/.local/bin/start_vnc.sh`       | VNC / noVNC / dock                                              |
| `docker/usr/local/share/google-chrome-cdp/` | CDP profile 种子（`Preferences`、可选 `Bookmarks`）             |
| `docker/tmp/`                               | 构建安装脚本                                                    |
| `vendor/`                                   | 预取的 Chrome / Node 包；构建时 bind，不进镜像层                |
| `scripts/download-chrome-dep.sh`            | 下载 Chrome `.deb`                                              |
| `scripts/download-node-dep.sh`              | 下载 Node linux-x64                                             |
| `Dockerfile`                                | 镜像构建                                                        |
| `AGENTS.md`                                 | 给 AI 的容器能力说明                                            |
