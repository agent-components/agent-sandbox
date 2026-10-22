## 语言

- Node.js v24.22.0：`node`
- Python 3.13：`python3`

## 浏览器

`launch-chrome-cdp`：未打开时启动浏览器并打开调试端口 `127.0.0.1:9222`；已在前台时最小化；已最小化或不在前台时恢复到前台。关掉浏览器窗口后，调试端口一并退出。

```bash
launch-chrome-cdp
```

`playwright-cli` 通过 CDP `http://127.0.0.1:9222` 操作浏览器。

```bash
playwright-cli attach --cdp=http://127.0.0.1:9222
playwright-cli goto https://example.com
playwright-cli snapshot
playwright-cli click e3
playwright-cli screenshot --filename=/opt/downloads/shot.png
```

## 桌面截图

使用 `scrot`。

```bash
scrot /opt/downloads/desktop.png
```

## 桌面键鼠

使用 `xdotool`。页面内操作使用 `playwright-cli`。

```bash
xdotool mousemove 960 540 click 1
xdotool type 'hello'
xdotool key Return
```
