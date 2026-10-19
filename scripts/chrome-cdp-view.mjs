#!/usr/bin/env node
import http from 'node:http';

const PORT = 9333;
const TOKEN = process.env.CDP_VIEW_TOKEN || '';
if (!TOKEN) {
  console.error('CDP_VIEW_TOKEN is required');
  process.exit(1);
}
const clients = new Set();
let latest = null;
let cdp = null;
let attachedId = '';
let nextId = 1;
let screenshotTimer = null;
/** @type {{ deviceWidth: number, deviceHeight: number, pageScaleFactor: number, offsetTop: number, scrollOffsetX: number, scrollOffsetY: number } | null} */
let lastMeta = null;
let lastJpegWidth = 0;
let lastJpegHeight = 0;

async function listPages() {
  const response = await fetch('http://127.0.0.1:9222/json/list');
  const targets = await response.json();
  return targets.filter((target) => target.type === 'page' && target.webSocketDebuggerUrl);
}

function send(method, params = {}) {
  if (!cdp || cdp.readyState !== WebSocket.OPEN) return false;
  cdp.send(JSON.stringify({ id: nextId++, method, params }));
  return true;
}

function broadcast(jpeg) {
  latest = jpeg;
  for (const response of clients) {
    response.write(`--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ${jpeg.length}\r\n\r\n`);
    response.write(jpeg);
    response.write('\r\n');
  }
}

/** Minimal SOF0/SOF2 scan to get JPEG dimensions without full decode. */
function jpegSize(buf) {
  if (!buf || buf.length < 4 || buf[0] !== 0xff || buf[1] !== 0xd8) return null;
  let i = 2;
  while (i + 9 < buf.length) {
    if (buf[i] !== 0xff) {
      i += 1;
      continue;
    }
    const marker = buf[i + 1];
    if (marker === 0xd9 || marker === 0xda) break;
    const len = (buf[i + 2] << 8) | buf[i + 3];
    if (len < 2) break;
    // SOF0..SOF3, SOF5..SOF7, SOF9..SOF11, SOF13..SOF15
    if (
      (marker >= 0xc0 && marker <= 0xc3) ||
      (marker >= 0xc5 && marker <= 0xc7) ||
      (marker >= 0xc9 && marker <= 0xcb) ||
      (marker >= 0xcd && marker <= 0xcf)
    ) {
      const height = (buf[i + 5] << 8) | buf[i + 6];
      const width = (buf[i + 7] << 8) | buf[i + 8];
      return { width, height };
    }
    i += 2 + len;
  }
  return null;
}

async function ensurePage() {
  let pages = await listPages();
  if (pages.length) return pages[0];
  // Last window closed may leave Chrome with no page targets while 9222 is still up.
  try {
    const created = await fetch('http://127.0.0.1:9222/json/new?about:blank', {
      method: 'PUT',
    });
    if (!created.ok) {
      await fetch('http://127.0.0.1:9222/json/new?about:blank');
    }
  } catch {
    // CDP may be fully down; entrypoint monitor will restart Chrome.
  }
  pages = await listPages();
  return pages[0];
}

async function attach() {
  const page = await ensurePage();
  if (!page) return;
  if (page.id === attachedId && cdp && cdp.readyState === WebSocket.OPEN) return;
  if (cdp) {
    cdp.close();
    cdp = null;
  }
  attachedId = page.id;
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  cdp = ws;
  ws.addEventListener('open', () => {
    send('Page.enable');
    send('Page.startScreencast', {
      format: 'jpeg',
      quality: 60,
      maxWidth: 1280,
      maxHeight: 800,
      everyNthFrame: 1,
    });
  });
  ws.addEventListener('message', async (event) => {
    let text = event.data;
    if (typeof text !== 'string') text = await text.text();
    const message = JSON.parse(text);
    if (message.method === 'Page.screencastFrame') {
      const jpeg = Buffer.from(message.params.data, 'base64');
      const size = jpegSize(jpeg);
      if (size) {
        lastJpegWidth = size.width;
        lastJpegHeight = size.height;
      }
      if (message.params.metadata) {
        lastMeta = message.params.metadata;
      }
      broadcast(jpeg);
      send('Page.screencastFrameAck', { sessionId: message.params.sessionId });
    } else if (message.result && message.result.data && !message.method) {
      const jpeg = Buffer.from(message.result.data, 'base64');
      const size = jpegSize(jpeg);
      if (size) {
        lastJpegWidth = size.width;
        lastJpegHeight = size.height;
      }
      broadcast(jpeg);
    }
  });
  ws.addEventListener('close', () => {
    if (cdp === ws) {
      cdp = null;
      attachedId = '';
    }
  });
}

function capture() {
  send('Page.captureScreenshot', { format: 'jpeg', quality: 50 });
}

/**
 * Map JPEG-pixel click to CSS viewport coords for Input.dispatchMouseEvent.
 * Screencast JPEG is a scaled view of the layout viewport.
 */
function jpegToCss(jx, jy) {
  if (!lastMeta || !lastJpegWidth || !lastJpegHeight) {
    return { x: jx, y: jy };
  }
  const scaleX = lastMeta.deviceWidth / lastJpegWidth;
  const scaleY = lastMeta.deviceHeight / lastJpegHeight;
  return {
    x: jx * scaleX,
    y: jy * scaleY + (lastMeta.offsetTop || 0),
  };
}

function dispatchClick(jx, jy, button = 'left') {
  const { x, y } = jpegToCss(jx, jy);
  const btn = button === 'right' ? 'right' : button === 'middle' ? 'middle' : 'left';
  const buttonsBit = btn === 'left' ? 1 : btn === 'right' ? 2 : 4;
  if (!send('Input.dispatchMouseEvent', {
    type: 'mousePressed',
    x,
    y,
    button: btn,
    buttons: buttonsBit,
    clickCount: 1,
  })) {
    return false;
  }
  send('Input.dispatchMouseEvent', {
    type: 'mouseReleased',
    x,
    y,
    button: btn,
    buttons: 0,
    clickCount: 1,
  });
  return true;
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    request.on('data', (chunk) => {
      total += chunk.length;
      if (total > 64 * 1024) {
        reject(new Error('body too large'));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    request.on('error', reject);
  });
}

const pageHtml = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Chrome</title>
  <style>
    html, body { margin: 0; height: 100%; background: #111; overflow: hidden; }
    img { width: 100%; height: 100%; object-fit: contain; background: #111; display: block; }
    img.interactive { cursor: crosshair; }
  </style>
</head>
<body>
  <img alt="" id="view">
  <script>
    const token = ${JSON.stringify(TOKEN)};
    const params = new URLSearchParams(location.search);
    const interactive =
      params.get('click') === '1' ||
      params.get('interactive') === '1' ||
      params.get('click') === 'true' ||
      params.get('interactive') === 'true';
    const img = document.getElementById('view');
    img.src = '/stream?token=' + encodeURIComponent(token);
    if (interactive) {
      img.classList.add('interactive');
      function mapToJpeg(e) {
        const rect = img.getBoundingClientRect();
        const nw = img.naturalWidth || 0;
        const nh = img.naturalHeight || 0;
        if (!nw || !nh) return null;
        const scale = Math.min(rect.width / nw, rect.height / nh);
        const dispW = nw * scale;
        const dispH = nh * scale;
        const ox = rect.left + (rect.width - dispW) / 2;
        const oy = rect.top + (rect.height - dispH) / 2;
        const jx = (e.clientX - ox) / scale;
        const jy = (e.clientY - oy) / scale;
        if (jx < 0 || jy < 0 || jx > nw || jy > nh) return null;
        return { x: jx, y: jy };
      }
      img.addEventListener('contextmenu', (e) => e.preventDefault());
      img.addEventListener('pointerdown', async (e) => {
        e.preventDefault();
        const pt = mapToJpeg(e);
        if (!pt) return;
        const button = e.button === 2 ? 'right' : e.button === 1 ? 'middle' : 'left';
        try {
          await fetch('/click?token=' + encodeURIComponent(token), {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ x: pt.x, y: pt.y, button }),
          });
        } catch (err) {
          console.error(err);
        }
      });
    }
  </script>
</body>
</html>`;

function tokenOk(url, request) {
  const given =
    url.searchParams.get('token') ||
    (request.headers['x-cdp-view-token'] || '');
  return given === TOKEN;
}

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1');
  const given = url.searchParams.get('token');
  if (given && given !== TOKEN) {
    response.writeHead(401, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end('unauthorized');
    return;
  }
  if (url.pathname === '/stream') {
    if (given !== TOKEN) {
      response.writeHead(401, { 'Content-Type': 'text/plain; charset=utf-8' });
      response.end('unauthorized');
      return;
    }
    response.writeHead(200, {
      'Content-Type': 'multipart/x-mixed-replace; boundary=frame',
      'Cache-Control': 'no-cache, no-store',
      'Connection': 'close',
      'X-Accel-Buffering': 'no',
    });
    clients.add(response);
    if (latest) {
      response.write(`--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ${latest.length}\r\n\r\n`);
      response.write(latest);
      response.write('\r\n');
    }
    request.on('close', () => clients.delete(response));
    return;
  }
  if (url.pathname === '/click' && request.method === 'POST') {
    if (!tokenOk(url, request)) {
      response.writeHead(401, { 'Content-Type': 'text/plain; charset=utf-8' });
      response.end('unauthorized');
      return;
    }
    try {
      const raw = await readBody(request);
      const body = JSON.parse(raw || '{}');
      const x = Number(body.x);
      const y = Number(body.y);
      if (!Number.isFinite(x) || !Number.isFinite(y)) {
        response.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
        response.end('bad coordinates');
        return;
      }
      const ok = dispatchClick(x, y, body.button || 'left');
      if (!ok) {
        response.writeHead(503, { 'Content-Type': 'text/plain; charset=utf-8' });
        response.end('cdp not ready');
        return;
      }
      response.writeHead(204);
      response.end();
    } catch (err) {
      response.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
      response.end(String(err.message || err));
    }
    return;
  }
  response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
  response.end(pageHtml);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`CDP view listening on 0.0.0.0:${PORT}`);
});

setInterval(() => {
  attach().catch((error) => console.error(error.message));
}, 1000);
screenshotTimer = setInterval(capture, 500);
attach().catch((error) => console.error(error.message));
