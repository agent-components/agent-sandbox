#!/usr/bin/env python3
"""noVNC websockify plus POST /upload on the same HTTPS port.

Body is the raw file. Filename is the X-Filename header (percent-encoded)
or ?name=. Auth is the same NOVNC_TOKEN as the websocket (?token= or
Authorization: Bearer). Files land in SANDBOX_UPLOAD_DIR (default
/data/uploads).
"""
import hmac
import json
import os
import sys
from urllib.parse import parse_qs, unquote, urlparse

UPLOAD_DIR = os.environ.get("SANDBOX_UPLOAD_DIR", "/data/uploads")
MAX_BYTES = int(os.environ.get("SANDBOX_UPLOAD_MAX_BYTES", str(200 * 1024 * 1024)))


def _token_ok(handler):
    expected = os.environ.get("NOVNC_TOKEN", "")
    if not expected:
        return False
    parsed = urlparse(handler.path)
    got = (parse_qs(parsed.query).get("token") or [""])[0]
    if not got:
        auth = handler.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            got = auth[7:].strip()
    try:
        return hmac.compare_digest(got, expected)
    except (TypeError, ValueError):
        return False


def _safe_rel(raw):
    """Relative path under the upload dir. Slashes are kept so a dropped folder stays a folder."""
    text = unquote(raw or "").replace("\\", "/").strip()
    if not text or text.startswith("/"):
        return ""
    parts = []
    for part in text.split("/"):
        part = part.strip()
        if part in ("", "."):
            continue
        if part == "..":
            return ""
        cleaned = []
        for ch in part:
            if ch in "/\\" or ord(ch) < 32:
                continue
            cleaned.append(ch)
        part = "".join(cleaned).strip().strip(".")
        if not part or part in (".", ".."):
            return ""
        if len(part) > 180:
            root, ext = os.path.splitext(part)
            part = root[:160] + ext[:20]
        parts.append(part)
    return "/".join(parts)


def _dest_path(rel):
    os.makedirs(UPLOAD_DIR, mode=0o755, exist_ok=True)
    root = os.path.realpath(UPLOAD_DIR)
    base, ext = os.path.splitext(rel)
    candidate = rel
    n = 2
    while n < 1000:
        path = os.path.join(UPLOAD_DIR, *candidate.split("/"))
        parent = os.path.realpath(os.path.dirname(path))
        if parent != root and not parent.startswith(root + os.sep):
            return ""
        if not os.path.exists(path):
            os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
            return path
        candidate = "%s (%d)%s" % (base, n, ext)
        n += 1
    return ""


def _json_response(handler, status, payload):
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


def do_POST(self):
    # Avoid keep-alive desync when the body is not fully consumed.
    self.close_connection = True
    parsed = urlparse(self.path)
    if parsed.path.rstrip("/") != "/upload":
        self.send_error(404, "Not found")
        return
    if not _token_ok(self):
        self.send_error(403, "Forbidden")
        return
    try:
        length = int(self.headers.get("Content-Length", "0"))
    except ValueError:
        self.send_error(400, "Bad Content-Length")
        return
    if length <= 0:
        self.send_error(400, "Empty body")
        return
    if length > MAX_BYTES:
        self.send_error(413, "File too large")
        return
    name = _safe_rel(self.headers.get("X-Filename", ""))
    if not name:
        name = _safe_rel((parse_qs(parsed.query).get("name") or [""])[0])
    if not name:
        self.send_error(400, "Missing filename")
        return
    dest = _dest_path(name)
    if not dest:
        self.send_error(400, "Bad filename")
        return
    tmp = dest + ".part-%d" % os.getpid()
    try:
        remaining = length
        with open(tmp, "wb") as out:
            while remaining:
                chunk = self.rfile.read(min(1024 * 1024, remaining))
                if not chunk:
                    raise OSError("short body")
                out.write(chunk)
                remaining -= len(chunk)
        os.replace(tmp, dest)
    except Exception as exc:
        sys.stderr.write("upload failed: %s\n" % exc)
        try:
            os.remove(tmp)
        except OSError:
            pass
        self.send_error(500, "Write failed")
        return
    _json_response(self, 200, {
        "ok": True,
        "name": os.path.basename(dest),
        "path": dest,
    })


def main():
    try:
        from websockify.websocketproxy import ProxyRequestHandler, websockify_init
    except Exception as exc:
        sys.stderr.write("novnc upload disabled (%s); starting stock websockify\n" % exc)
        os.execvp("websockify", ["websockify", *sys.argv[1:]])
    ProxyRequestHandler.do_POST = do_POST
    # Unlabeled text/html is sniffed as GBK in a Chinese locale.
    _guess_type = ProxyRequestHandler.guess_type

    def guess_type(self, path):
        ctype = _guess_type(self, path)
        if ctype == "text/html":
            return "text/html; charset=utf-8"
        return ctype

    ProxyRequestHandler.guess_type = guess_type
    websockify_init()


if __name__ == "__main__":
    main()
