import gzip, json, random, struct, sys, time, zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

LOG = open("results.log", "a", buffering=1)
random.seed(1)

def synthetic(w, h):
    """White page with text-like black runs and a few grey blocks, like a typical screen."""
    rows = []
    for y in range(h):
        row = bytearray(b"\xff" * w)
        if (y // 18) % 2 == 0 and y > 60:
            x = 60
            while x < w - 60:
                run = random.randint(2, 9)
                if random.random() < 0.7:
                    for i in range(x, min(x + run, w - 60)): row[i] = 0 if random.random() < .85 else 128
                x += run + random.randint(1, 5)
        rows.append(bytes(row))
    return rows

def png(rows, w, h):
    raw = b"".join(b"\x00" + r for r in rows)
    def chunk(t, d): c = struct.pack(">I", len(d)) + t + d; return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 1)) + chunk(b"IEND", b"")

cache = {}
def frame(w, h):
    if (w, h) not in cache:
        rows = synthetic(w, h); cache[(w, h)] = (b"".join(rows), png(rows, w, h))
    return cache[(w, h)]

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        u = urlparse(self.path); q = {k: v[0] for k, v in parse_qs(u.query).items()}
        if u.path in ("/", "/index.html"):
            body = open("index.html", "rb").read(); ctype = "text/html"
        elif u.path == "/raw":
            w, h = int(q["w"]), int(q["h"]); body = frame(w, h)[0]; ctype = "application/octet-stream"
            if q.get("gz") == "1": body = gzip.compress(body, 1); self.send_response(200); self.send_header("Content-Encoding", "gzip"); self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(body))); self.send_header("Cache-Control", "no-store"); self.end_headers(); self.wfile.write(body); return
        elif u.path == "/png":
            w, h = int(q["w"]), int(q["h"]); body = frame(w, h)[1]; ctype = "image/png"
        else:
            self.send_response(404); self.end_headers(); return
        self.send_response(200); self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(body))); self.send_header("Cache-Control", "no-store"); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0)); LOG.write(self.rfile.read(n).decode() + "\n")
        self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers()

ThreadingHTTPServer(("127.0.0.1", 8765), H).serve_forever()
