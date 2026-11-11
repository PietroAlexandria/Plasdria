#!/usr/bin/env python3
"""Servidor de medição de mentira (mesma interface da Cloudflare) para os testes do teste de velocidade.

  GET  /__down?bytes=N  envia N bytes
  POST /__up            recebe e descarta o corpo

Uso: fake_speed_server.py <porta>   (encerra sozinho depois de 120 s)
"""
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

CHUNK = b"x" * 65536


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_GET(self):
        url = urlparse(self.path)
        if url.path != "/__down":
            self.send_error(404)
            return
        remaining = int(parse_qs(url.query).get("bytes", ["0"])[0])
        self.send_response(200)
        self.send_header("Content-Length", str(remaining))
        self.send_header("cf-ray", "abc123-GRU")
        self.end_headers()
        try:
            while remaining > 0:
                piece = CHUNK[: min(remaining, len(CHUNK))]
                self.wfile.write(piece)
                remaining -= len(piece)
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True

    def do_POST(self):
        if self.path != "/__up":
            self.send_error(404)
            return
        left = int(self.headers.get("Content-Length", "0"))
        try:
            while left > 0:
                data = self.rfile.read(min(left, 65536))
                if not data:
                    break
                left -= len(data)
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler)
    server.daemon_threads = True
    threading.Timer(120, server.shutdown).start()
    server.serve_forever()
