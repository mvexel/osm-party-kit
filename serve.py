#!/usr/bin/env python3
"""Serve osmlogo on the local network so a room full of mappers can join.

python3 serve.py [port]     (default 8765)

Plain stdlib. Two additions over http.server:
- Range request support, which DuckDB-WASM needs to scan the baked parquet.
- The scribble API: POST /api/scribble appends one JSON line to
  party/scribbles.jsonl; clients poll that file. Dumb on purpose — the
  append-only file is the shared state, the sync protocol, and the report
  input all at once. Erasing is a tombstone line, never a rewrite.
"""
import json
import os
import re
import socket
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
ROOT = os.path.dirname(os.path.abspath(__file__))
RANGE_RE = re.compile(r"bytes=(\d*)-(\d*)")
SCRIBBLES = os.path.join(ROOT, "party", "scribbles.jsonl")
SCRIBBLE_LOCK = threading.Lock()
MAX_SCRIBBLE_BYTES = 64 * 1024  # one freehand line; anything bigger is abuse/bug


def valid_scribble(msg):
    if not isinstance(msg, dict) or not isinstance(msg.get("id"), str) or len(msg["id"]) > 32:
        return False
    if msg.get("t") == "e":  # erase tombstone
        return True
    if msg.get("t") != "s" or not isinstance(msg.get("c"), str) or len(msg["c"]) > 16:
        return False
    if not isinstance(msg.get("h", ""), str) or len(msg.get("h", "")) > 24:
        return False  # handle: self-declared name, optional, capped
    pts = msg.get("pts")
    return (isinstance(pts, list) and 2 <= len(pts) <= 2000 and
            all(isinstance(p, list) and len(p) == 2 and
                all(isinstance(v, (int, float)) for v in p) for p in pts))


class RangeHandler(SimpleHTTPRequestHandler):
    range = None  # end_headers can run before send_head (e.g. send_error on a bad request)

    def send_head(self):
        if self.path == "/":
            self.send_response(301)
            self.send_header("Location", "/web/")
            self.end_headers()
            return None
        if self.path.startswith("/api/ping"):
            # scribble-capability probe: static hosts 404 this, so the web
            # app knows to hide the draw tools
            self.send_response(204)
            self.end_headers()
            return None
        self.range = None
        m = RANGE_RE.match(self.headers.get("Range", ""))
        if not m:
            return super().send_head()
        path = self.translate_path(self.path)
        try:
            f = open(path, "rb")
        except OSError:
            self.send_error(404, "File not found")
            return None
        size = os.fstat(f.fileno()).st_size
        start = int(m.group(1)) if m.group(1) else size - int(m.group(2))
        end = int(m.group(2)) if m.group(1) and m.group(2) else size - 1
        end = min(end, size - 1)
        if start > end or start >= size:
            f.close()
            self.send_error(416, "Requested Range Not Satisfiable")
            return None
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(end - start + 1))
        self.end_headers()
        self.range = (start, end)
        f.seek(start)
        return f

    def copyfile(self, source, outputfile):
        if self.range is None:
            return super().copyfile(source, outputfile)
        remaining = self.range[1] - self.range[0] + 1
        while remaining > 0:
            chunk = source.read(min(64 * 1024, remaining))
            if not chunk:
                break
            outputfile.write(chunk)
            remaining -= len(chunk)

    def do_POST(self):
        if self.path != "/api/scribble":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", 0))
        if not 0 < length <= MAX_SCRIBBLE_BYTES:
            self.send_error(413)
            return
        try:
            msg = json.loads(self.rfile.read(length))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self.send_error(400)
            return
        if not valid_scribble(msg):
            self.send_error(400)
            return
        line = json.dumps({**msg, "ts": round(time.time())}, separators=(",", ":"))
        with SCRIBBLE_LOCK:
            with open(SCRIBBLES, "a") as f:
                f.write(line + "\n")
        self.send_response(204)
        self.end_headers()

    def end_headers(self):
        if self.range is None:
            self.send_header("Accept-Ranges", "bytes")
        if self.path.startswith("/party/"):
            self.send_header("Cache-Control", "no-store")  # clients poll this
        super().end_headers()

    def log_message(self, *args):
        pass  # keep the terminal readable for the URL below


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))  # no packets sent; just picks the route
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


if __name__ == "__main__":
    os.chdir(ROOT)
    os.makedirs(os.path.dirname(SCRIBBLES), exist_ok=True)
    if not os.path.exists(SCRIBBLES):
        open(SCRIBBLES, "a").close()  # so first poll is a 200, not a 404
    host = socket.gethostname().removesuffix(".local").lower()
    print(f"\n  🐢 osmlogo is up — everyone on this network can join:\n")
    print(f"     http://{host}.local:{PORT}   (type this on laptops — mDNS)")
    print(f"     http://{lan_ip()}:{PORT}   (fallback if .local doesn't resolve)\n")
    print("  (open it yourself and hit 'share' to show a QR for phones)")
    print("  Ctrl-C to stop.\n")
    ThreadingHTTPServer(("", PORT), RangeHandler).serve_forever()
