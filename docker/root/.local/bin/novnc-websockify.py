#!/usr/bin/env python3
"""noVNC websockify plus file transfer on the same HTTPS port.

POST /upload: body is the raw file. Filename is the X-Filename header
(percent-encoded) or ?name=. Files land in SANDBOX_UPLOAD_DIR (default
/data/uploads).

GET /download?path=: one regular file. path is absolute and must stay
inside SANDBOX_DOWNLOAD_ROOTS (default /data:/home/workspace).
A single Range: bytes=start-end is answered with 206 so the browser can
resume. HEAD returns the same headers and no body.

Auth for both is the same NOVNC_TOKEN as the websocket (?token= or
Authorization: Bearer). Size limit is SANDBOX_UPLOAD_MAX_BYTES (default
200MB) for a single upload or download.
"""
import hmac
import json
import os
import re
import stat
import sys
from urllib.parse import parse_qs, quote, unquote, urlparse

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


def _download_roots():
    raw = os.environ.get("SANDBOX_DOWNLOAD_ROOTS", "/data:/home/workspace")
    roots = []
    for part in raw.split(":"):
        part = part.strip()
        if not part:
            continue
        if part != "/":
            part = part.rstrip("/")
        roots.append(os.path.realpath(part))
    return roots


def _under_root(real, root):
    if not real or real == root:
        return False
    if root == "/":
        return real.startswith("/")
    return real.startswith(root + os.sep)


def _resolve_download(raw):
    """Absolute path of one regular file inside a download root, or ''."""
    text = (raw or "").strip()
    if not text or not text.startswith("/") or any(ord(ch) < 32 for ch in text):
        return ""
    real = os.path.realpath(text)
    if not any(_under_root(real, root) for root in _download_roots()):
        return ""
    try:
        st = os.stat(real)
    except OSError:
        return ""
    if not stat.S_ISREG(st.st_mode):
        return ""
    return real


_RANGE_RE = re.compile(r"bytes=(\d*)-(\d*)$")


def _parse_byte_range(header, size):
    """One inclusive (start, end), None for the whole file, False if 416.

    Only a single bytes range. A multipart Range is ignored so the caller
    sends the whole file; browsers resume with one range.
    """
    if not header:
        return None
    header = header.strip()
    if "," in header:
        return None
    match = _RANGE_RE.match(header)
    if not match:
        return None
    start_s, end_s = match.group(1), match.group(2)
    if start_s == "" and end_s == "":
        return None
    if size < 0:
        return False
    if start_s == "":
        length = int(end_s)
        if length <= 0 or size == 0:
            return False
        if length >= size:
            return (0, size - 1)
        return (size - length, size - 1)
    start = int(start_s)
    if start >= size:
        return False
    if end_s == "":
        end = size - 1
    else:
        end = int(end_s)
        if end < start:
            return False
        if end >= size:
            end = size - 1
    return (start, end)


def _if_range_matches(header, etag, last_modified):
    if not header:
        return True
    value = header.strip()
    if value.startswith('"') or value.startswith("W/"):
        return value == etag
    return value == last_modified


def _content_disposition(filename):
    fallback = []
    for ch in filename:
        if 32 <= ord(ch) < 127 and ch not in '"\\':
            fallback.append(ch)
        else:
            fallback.append("_")
    ascii_name = "".join(fallback).strip(" .") or "download"
    encoded = quote(filename, safe="")
    return "attachment; filename=\"%s\"; filename*=UTF-8''%s" % (ascii_name, encoded)


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


def _download_headers(handler, dest, st, status, length, content_range):
    etag = '"%x-%x"' % (st.st_mtime_ns, st.st_size)
    last_modified = handler.date_time_string(st.st_mtime)
    handler.send_response(status)
    handler.send_header("Content-Type", "application/octet-stream")
    handler.send_header("Content-Disposition", _content_disposition(os.path.basename(dest)))
    handler.send_header("Accept-Ranges", "bytes")
    handler.send_header("ETag", etag)
    handler.send_header("Last-Modified", last_modified)
    handler.send_header("Content-Length", str(length))
    if content_range:
        handler.send_header("Content-Range", content_range)
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("X-Content-Type-Options", "nosniff")
    handler.end_headers()
    return etag, last_modified


def _do_download(handler, parsed, head_only=False):
    handler.close_connection = True
    if not _token_ok(handler):
        handler.send_error(403, "Forbidden")
        return
    raw = (parse_qs(parsed.query).get("path") or [""])[0]
    dest = _resolve_download(raw)
    if not dest:
        handler.send_error(404, "Not found")
        return
    try:
        fh = open(dest, "rb")
    except OSError as exc:
        sys.stderr.write("download open failed: %s\n" % exc)
        handler.send_error(404, "Not found")
        return
    try:
        st = os.fstat(fh.fileno())
        size = st.st_size
        if size > MAX_BYTES:
            handler.send_error(413, "File too large")
            return
        etag = '"%x-%x"' % (st.st_mtime_ns, size)
        last_modified = handler.date_time_string(st.st_mtime)
        span = _parse_byte_range(handler.headers.get("Range"), size)
        if span is not None and not _if_range_matches(handler.headers.get("If-Range"), etag, last_modified):
            span = None
        if span is False:
            handler.send_response(416)
            handler.send_header("Content-Range", "bytes */%d" % size)
            handler.send_header("Accept-Ranges", "bytes")
            handler.send_header("Content-Length", "0")
            handler.send_header("Cache-Control", "no-store")
            handler.end_headers()
            return
        if span is None:
            start = 0
            end = size - 1
            status = 200
            content_range = None
        else:
            start, end = span
            status = 206
            content_range = "bytes %d-%d/%d" % (start, end, size)
        length = 0 if end < start else end - start + 1
        _download_headers(handler, dest, st, status, length, content_range)
        if head_only or length == 0:
            return
        fh.seek(start)
        remaining = length
        while remaining:
            chunk = fh.read(min(1024 * 1024, remaining))
            if not chunk:
                break
            handler.wfile.write(chunk)
            remaining -= len(chunk)
    except Exception as exc:
        sys.stderr.write("download failed: %s\n" % exc)
    finally:
        fh.close()


def main():
    try:
        from websockify.websocketproxy import ProxyRequestHandler, websockify_init
    except Exception as exc:
        sys.stderr.write("novnc file transfer disabled (%s); starting stock websockify\n" % exc)
        os.execvp("websockify", ["websockify", *sys.argv[1:]])
    ProxyRequestHandler.do_POST = do_POST
    _orig_do_GET = ProxyRequestHandler.do_GET
    _orig_do_HEAD = getattr(ProxyRequestHandler, "do_HEAD", None)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path.rstrip("/") == "/download":
            _do_download(self, parsed, head_only=False)
            return
        return _orig_do_GET(self)

    def do_HEAD(self):
        parsed = urlparse(self.path)
        if parsed.path.rstrip("/") == "/download":
            _do_download(self, parsed, head_only=True)
            return
        if _orig_do_HEAD is not None:
            return _orig_do_HEAD(self)
        self.send_error(501, "Unsupported method ('HEAD')")

    ProxyRequestHandler.do_GET = do_GET
    ProxyRequestHandler.do_HEAD = do_HEAD
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
