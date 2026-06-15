#!/usr/bin/env python3
"""Minimal HTTPS CONNECT proxy with a /metrics endpoint.

Plain HTTP (no inbound TLS):
    python3 kms_http_proxy.py [--host 127.0.0.1] [--port 8080]

    $ curl --proxy 127.0.0.1:8080 -sS -o /dev/null https://example.com
    $ curl http://127.0.0.1:8080/metrics

TLS on the inbound connection (clients must connect over HTTPS):
    python3 kms_http_proxy.py --port 8443 --ca_file ca.pem --cert_file server.pem

    $ curl --proxy-cacert ca.pem --proxy https://127.0.0.1:8443 -sS -o /dev/null https://example.com
    $ curl -k https://127.0.0.1:8443/metrics

Behavior:
  - CONNECT host:port HTTP/1.1  -> opens a TCP tunnel, returns 200, then
                                   blindly proxies bytes both directions.
  - GET /metrics                -> returns "connect_count <N>\\n" so callers
                                   can verify a CONNECT was observed.
  - POST /reset                 -> resets the connection count to 0.
  - Any other request           -> 404.

No auth, no concurrency limits. For local testing only.
"""

from __future__ import annotations

import argparse
import select
import socket
import ssl
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


def _reset_metrics() -> None:
    global _connect_count, _connect_targets
    with _counter_lock:
        _connect_count = 0
        _connect_targets = []


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

    # ---- POST /reset ------------------------------------------------------
    def do_POST(self) -> None:
        if self.path != "/reset":
            self.send_error(404, "only /reset is exposed")
            return
        _reset_metrics()
        body = b"connect_count 0\n"
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
    p.add_argument("--ca_file", type=str, default=None, help="TLS CA PEM file")
    p.add_argument("--cert_file", type=str, default=None, help="TLS server PEM file (required with --ca_file)")
    args = p.parse_args()

    if bool(args.ca_file) != bool(args.cert_file):
        p.error("--ca_file and --cert_file must be given together")

    server = ThreadingHTTPServer((args.host, args.port), ProxyHandler)

    if args.ca_file:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_verify_locations(args.ca_file)
        context.load_cert_chain(args.cert_file)
        context.verify_mode = ssl.CERT_NONE
        server.socket = context.wrap_socket(server.socket, server_side=True)
        scheme = "https"
    else:
        scheme = "http"

    sys.stderr.write(f"KMS HTTP proxy listening on {args.host}:{args.port}\n")
    sys.stderr.write(f"  metrics:   {scheme}://{args.host}:{args.port}/metrics\n")
    sys.stderr.write(f"  reset:     {scheme}://{args.host}:{args.port}/reset\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.stderr.write("shutting down\n")
        server.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
