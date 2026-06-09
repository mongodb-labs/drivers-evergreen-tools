#!/usr/bin/env python3
"""Minimal HTTPS CONNECT proxy with a /metrics endpoint.

Run:
    python3 kms_http_proxy.py [--host 127.0.0.1] [--port 8080]

To test:

    $ curl --proxy 127.0.0.1:8080 -sS -o /dev/null https://example.com
    $ curl http://127.0.0.1:8080/metrics
    connect_count 1
    connect_target example.com:443

Behavior:
  - CONNECT host:port HTTP/1.1  -> opens a TCP tunnel, returns 200, then
                                   blindly proxies bytes both directions.
  - GET /metrics                -> returns "connect_count <N>\n" so callers
                                   can verify a CONNECT was observed.
  - Any other request           -> 405.

No auth, no TLS on the inbound side, no concurrency limits. This is for
local testing only.
"""

from __future__ import annotations

import argparse
import select
import socket
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

_counter_lock = threading.Lock()
_connect_count = 0
_connect_targets: list[str] = []


def _bump_connect(target: str) -> None:
    global _connect_count
    with _counter_lock:
        _connect_count += 1
        _connect_targets.append(target)


def _snapshot_metrics() -> tuple[int, list[str]]:
    with _counter_lock:
        return _connect_count, list(_connect_targets)


class ProxyHandler(BaseHTTPRequestHandler):
    # BaseHTTPRequestHandler logs to stderr by default; keep it but make it terse.
    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("[proxy %s] %s\n" % (self.address_string(), fmt % args))

    # ---- HTTPS CONNECT ----------------------------------------------------
    def do_CONNECT(self) -> None:
        # self.path is "host:port"
        target = self.path
        try:
            host, port_s = target.rsplit(":", 1)
            port = int(port_s)
        except ValueError:
            self.send_error(400, "bad CONNECT target")
            return

        try:
            upstream = socket.create_connection((host, port), timeout=10)
        except OSError as exc:
            self.send_error(502, f"upstream connect failed: {exc}")
            return

        _bump_connect(target)
        self.log_message(
            "CONNECT %s established (count=%d)", target, _snapshot_metrics()[0]
        )

        # 200 response with no body. BaseHTTPRequestHandler insists on a
        # Content-Length on end_headers(), but for CONNECT we just want the
        # bare status line + blank line.
        self.wfile.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        self.wfile.flush()

        client = self.connection
        try:
            _tunnel(client, upstream)
        finally:
            try:
                upstream.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            upstream.close()

    # ---- GET /metrics -----------------------------------------------------
    def do_GET(self) -> None:
        if self.path != "/metrics":
            self.send_error(404, "only /metrics is exposed")
            return
        count, targets = _snapshot_metrics()
        body_lines = [f"connect_count {count}"]
        body_lines.extend(f"connect_target {t}" for t in targets)
        body = ("\n".join(body_lines) + "\n").encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def _tunnel(a: socket.socket, b: socket.socket) -> None:
    """Pipe bytes between two sockets until either side closes."""
    sockets = [a, b]
    while True:
        try:
            ready, _, errored = select.select(sockets, [], sockets, 60)
        except (OSError, ValueError):
            return
        if errored:
            return
        if not ready:
            # idle; let it keep waiting
            continue
        for s in ready:
            peer = b if s is a else a
            try:
                data = s.recv(8192)
            except OSError:
                return
            if not data:
                return
            try:
                peer.sendall(data)
            except OSError:
                return


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8080)
    args = p.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), ProxyHandler)
    sys.stderr.write(f"KMS HTTP proxy listening on {args.host}:{args.port}\n")
    sys.stderr.write(f"  metrics:   http://{args.host}:{args.port}/metrics\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.stderr.write("shutting down\n")
        server.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
