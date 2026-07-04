#!/usr/bin/env python3
"""Serve osmlogo on the local network so a room full of mappers can join.

python3 serve.py [port]     (default 8765)

Plain stdlib. The one thing http.server lacks is Range request support,
which DuckDB-WASM needs to scan the baked parquet over HTTP — added here.
"""
import os
import re
import socket
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
ROOT = os.path.dirname(os.path.abspath(__file__))
RANGE_RE = re.compile(r"bytes=(\d*)-(\d*)")


class RangeHandler(SimpleHTTPRequestHandler):
    range = None  # end_headers can run before send_head (e.g. send_error on a bad request)

    def send_head(self):
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

    def end_headers(self):
        if self.range is None:
            self.send_header("Accept-Ranges", "bytes")
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
    url = f"http://{lan_ip()}:{PORT}/web/"
    print(f"\n  🐢 osmlogo is up — everyone on this network can join:\n")
    print(f"     {url}\n")
    print("  (open it yourself and hit 'share' to show a QR for the room)")
    print("  Ctrl-C to stop.\n")
    ThreadingHTTPServer(("", PORT), RangeHandler).serve_forever()
