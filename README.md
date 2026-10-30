# agent-sandbox 0.0.1（约 529.951 MB）

Linux 图形桌面容器：浏览器看桌面、Chrome 远程调试、单独查看并可点击 Chrome 画面。工作目录为 `/home/workspace`。

让 AI 协助操作前，请先让它阅读 [`AGENTS.md`](./AGENTS.md)（容器内语言、浏览器、终端、截图与键鼠约定）。

- **桌面**：浏览器打开 noVNC，默认 `1920×1080`
- **Chrome**：容器内 CDP `127.0.0.1:9222`，供自动化
- **Chrome 画面**：9333 端口单独查看，可点击操作
- **agent-gateway**：本机 Agent HTTP 网关（默认 `6090`），开机自启；契约见 [agent-gateway](https://github.com/agent-components/agent-gateway)
- **SSH**：开机自启 `sshd`（默认 `22`），供 Cursor / VS Code / JetBrains 等 IDE Remote SSH

## 快速开始（公开镜像）

镜像地址：`registry.cn-hangzhou.aliyuncs.com/agent-components/agent-sandbox:0.0.1`（公开拉取一般无需登录）。

```bash
docker pull registry.cn-hangzhou.aliyuncs.com/agent-components/agent-sandbox:0.0.1

docker rm -f agent-sandbox-test 2>/dev/null
docker run -d --name agent-sandbox-test --hostname desktop --shm-size=1g -m 2g \
  --security-opt seccomp=unconfined \
  -p 6080:6080 -p 9333:9333 -p 6090:6090 -p 2222:22 \
  -v agent-sandbox-data:/data \
  -e NOVNC_TOKEN=local-novnc-token \
  -e CDP_VIEW_TOKEN=local-cdp-token \
  -e CURSOR_API_KEY=cursor_... \
  -e AGENT_GATEWAY_TOKEN=local-gateway-token \
  -e SSH_PASSWORD=local-ssh-pass \
  registry.cn-hangzhou.aliyuncs.com/agent-components/agent-sandbox:0.0.1
```

`-v agent-sandbox-data:/data` 把整盘 `/data` 挂成卷，容器删掉后 Chrome 配置、下载等仍在（见「持久化 `/data`」）。

- `CURSOR_API_KEY`：使用 Cursor provider 时需要；未设则网关仍会启动，但 Cursor 调用不可用。
- `AGENT_GATEWAY_TOKEN`：API 鉴权；未设时进程会自动生成，见 `/data/log/agent-gateway/agent-gateway.log`。
- `SSH_PASSWORD` / `SSH_AUTHORIZED_KEYS`：至少配置一种，否则 sshd 会起但无法登录（也可用卷内 `/data/ssh/authorized_keys`）。

可选：再挂自备书签（见「默认书签」）：

```bash
  -v "$PWD/Bookmarks:/usr/local/share/google-chrome-cdp/Default/Bookmarks:ro" \
```

## 访问

| 入口          | 地址                                                                                                                                                                                                                                               |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 桌面（noVNC） | [https://127.0.0.1:6080/vnc_lite.html?autoconnect=1&reconnect=1&resize=scale&path=websockify%3Ftoken%3Dlocal-novnc-token](https://127.0.0.1:6080/vnc_lite.html?autoconnect=1&reconnect=1&resize=scale&path=websockify%3Ftoken%3Dlocal-novnc-token) |
| Chrome 画面   | [http://127.0.0.1:9333/?token=local-cdp-token&click=1](http://127.0.0.1:9333/?token=local-cdp-token&click=1)                                                                                                                                       |
| agent-gateway | [http://127.0.0.1:6090/](http://127.0.0.1:6090/)（Web 调试页）；机器可读契约 [http://127.0.0.1:6090/openapi.json](http://127.0.0.1:6090/openapi.json)                                                                                              |
| SSH           | `ssh -p 2222 root@127.0.0.1`（示例把容器 22 映射到宿主机 2222）                                                                                                                                                                                    |

- noVNC 为自签证书，浏览器需放行。
- 默认不自动开 Chrome；设 `SANDBOX_AUTO_START_CHROME=1` 可开机自启。
- agent-gateway API 需 `Authorization: Bearer <AGENT_GATEWAY_TOKEN>`；接口细节见上游文档。

## 端口

| 端口 | 用途                                  |
| ---- | ------------------------------------- |
| 6080 | noVNC HTTPS                           |
| 9333 | chrome-cdp-view MJPEG（需 `?token=`） |
| 6090 | agent-gateway HTTP（Web UI + API）    |
| 22   | SSH（建议宿主机映射如 `-p 2222:22`）  |

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
| `CURSOR_API_KEY`                | 否   | agent-gateway Cursor provider；未设则该 provider 不可用          |
| `AGENT_GATEWAY_TOKEN`           | 否   | 网关 API Bearer token；缺省自动生成并写入启动日志                |
| `AGENT_GATEWAY_CWD`             | 否   | 网关默认工作区，默认 `/home/workspace`                           |
| `AGENT_GATEWAY_HOME`            | 否   | 网关解压缓存 / 静态资源，默认 `/data/agent-gateway`              |
| `PORT` / `HOST`                 | 否   | 网关监听，默认 `6090` / `0.0.0.0`                                |
| `SSH_PASSWORD`                  | 否*  | root 密码；设置后启用密码登录                                    |
| `SSH_AUTHORIZED_KEYS`           | 否*  | 写入 `/root/.ssh/authorized_keys` 的公钥（可多行）               |
| `SSH_PORT`                      | 否   | 容器内 sshd 端口，默认 `22`                                      |

\* SSH 需密码、环境变量公钥或 `/data/ssh/authorized_keys` 至少一种。

## 持久化 `/data`

需要保留的数据放在 `/data` 下，并把整个 `/data` 挂到卷或宿主机目录，这样换镜像、删容器也不会丢：

| 路径                                | 内容                                                           |
| ----------------------------------- | -------------------------------------------------------------- |
| `/data/google-chrome`               | Chrome CDP `user-data-dir`（配置、书签等）                     |
| `/data/chrome-cache`                | Chrome `--disk-cache-dir`                                      |
| `/data/downloads`                   | Chrome 下载目录；截图等也可写这里                              |
| `/data/log`                         | noVNC / CDP / Chrome / agent-gateway 日志（可用 `LOG_DIR` 改） |
| `/data/agent-gateway`               | agent-gateway 解压缓存与静态 UI（`AGENT_GATEWAY_HOME`）        |
| `/data/ssh`                         | SSH 主机密钥 + 可选 `authorized_keys`（换容器后 IDE 少告警）   |
| `/data/npm`                         | npm cache（`npm_config_cache`）                                |
| `/data/npm-global`                  | 全局 npm 包（`npm_config_prefix`）                             |
| `/data/.playwright-cli`             | Playwright 产物（`PLAYWRIGHT_MCP_OUTPUT_DIR`）                 |
| `/data/.cache/ms-playwright/daemon` | Playwright daemon（`PLAYWRIGHT_DAEMON_SESSION_DIR`）           |

```bash
# Docker 命名卷（推荐）
-v agent-sandbox-data:/data

# 或绑到宿主机目录
-v "$PWD/data:/data"
```

工作目录 `/home/workspace` 不在 `/data` 内；要一并保留请另挂 `-v ...:/home/workspace`。

## agent-gateway

构建时把 `docker/tmp/agent-gateway` 装到 `/root/.local/bin/agent-gateway`；容器入口执行 `sh /tmp/install-agent-gateway.sh start` 后台拉起。

```bash
# 容器内手动控制
sh /tmp/install-agent-gateway.sh start
sh /tmp/install-agent-gateway.sh stop
```

日志：`$LOG_DIR/agent-gateway/agent-gateway.log`。协议与调用示例见 [agent-components/agent-gateway](https://github.com/agent-components/agent-gateway)。

## SSH（外部 IDE）

构建安装 `openssh-server`；入口执行 `sh /tmp/install-ssh.sh start`。用户 `root`，工作区建议打开 `/home/workspace`。

密码示例见上方 `docker run`。公钥可二选一：

```bash
# 环境变量（启动时写入 /root/.ssh/authorized_keys）
-e SSH_AUTHORIZED_KEYS="$(cat ~/.ssh/id_ed25519.pub)"

# 或持久化到卷
# 把公钥放到宿主机 data/ssh/authorized_keys 后挂 -v ...:/data
```

本机 `~/.ssh/config` 示例（Cursor / VS Code Remote SSH 可直接用）：

```sshconfig
Host agent-sandbox
  HostName 127.0.0.1
  Port 2222
  User root
  # IdentityFile ~/.ssh/id_ed25519
  StrictHostKeyChecking accept-new
```

```bash
ssh agent-sandbox
# 或
ssh -p 2222 root@127.0.0.1
```

日志：`$LOG_DIR/ssh/sshd.log`。主机密钥在 `/data/ssh/ssh_host_*`，与 `/data` 卷一起保留可减少换容器后的指纹提示。

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

| 路径                                        | 用途                                                              |
| ------------------------------------------- | ----------------------------------------------------------------- |
| `docker/root/`                              | → 容器 `/root/`（root 家目录）                                    |
| `docker/home/entrypoint.sh`                 | → `/home/entrypoint.sh`（SSH + agent-gateway + VNC；Chrome 按需或自启） |
| `docker/home/start/`                        | → `/home/start/`                                                        |
| `docker/root/.local/bin/start_vnc.sh`       | VNC / noVNC / dock                                                      |
| `docker/usr/local/share/google-chrome-cdp/` | CDP profile 种子（`Preferences`、可选 `Bookmarks`）                     |
| `docker/tmp/agent-gateway`                  | agent-gateway 一键二进制（构建时 install）                              |
| `docker/tmp/install-agent-gateway.sh`       | 安装 / 启停 agent-gateway                                               |
| `docker/tmp/install-ssh.sh`                 | 配置 / 启停 sshd（IDE Remote SSH）                                      |
| `docker/tmp/`                               | 构建安装脚本（Node / 桌面 / Chrome / SSH / agent-gateway）              |
| `vendor/`                                   | 预取的 Chrome / Node 包；构建时 bind，不进镜像层                  |
| `scripts/download-chrome-dep.sh`            | 下载 Chrome `.deb`                                                |
| `scripts/download-node-dep.sh`              | 下载 Node linux-x64                                               |
| `Dockerfile`                                | 镜像构建                                                          |
| `AGENTS.md`                                 | 给 AI 的容器能力说明                                              |
