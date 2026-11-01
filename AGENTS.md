## 语言

- Node.js v24.22.0：`node`
- Python 3.13：`python3`

## 浏览器

`launch-chrome-cdp`：未打开时启动浏览器并打开调试端口 `127.0.0.1:9222`；已在前台时最小化；已最小化或不在前台时恢复到前台。关掉浏览器窗口后，调试端口一并退出。

```bash
launch-chrome-cdp
```

容器只启动 Chrome 并监听 CDP `http://127.0.0.1:9222`，不会 attach。页面操作用调用方配好的 Playwright MCP（`@playwright/mcp --cdp-endpoint=http://127.0.0.1:9222`）。先执行 `launch-chrome-cdp`，再调用 MCP 工具；工具名以该 MCP 的 `tools/list` 为准。

## 终端

`launch-terminal`：在桌面打开 `xfce4-terminal`。标题栏无最小化按钮。日志在窗口内看；本命令几乎无 stdout。

**必须**带 `--title` / `-T`（同名会先关旧窗口再开，避免旧进程残留）。不要用不带 title 的调用。**禁止**自行设置 `DISPLAY`。

空终端：

```bash
launch-terminal --title='app'
```

启动时执行命令（`-e`；跑完还要留在 shell 里就加 `exec bash`）：

```bash
launch-terminal --title='app' \
  -e "bash -lc 'cd /home/workspace/my-app && npm start; exec bash'"
```

需要同时落盘时由调用方自己加 `tee`（路径尽量无空格，少嵌套转义）：

```bash
launch-terminal --title='app' \
  -e "bash -lc 'cd /home/workspace/my-app && npm start 2>&1 | tee /tmp/app.log; exec bash'"
```

## 桌面截图

使用 `scrot`。

```bash
scrot /data/downloads/desktop.png
```

## 桌面键鼠

使用 `xdotool`。页面内操作使用 Playwright MCP。

```bash
xdotool mousemove 960 540 click 1
xdotool type 'hello'
xdotool key Return
```
