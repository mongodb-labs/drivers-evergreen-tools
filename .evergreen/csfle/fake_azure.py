import argparse
import functools
import json
import time
import traceback
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any, Callable, Iterable


class HTTPResponse:
    "A non-200 response."

    def __init__(self, status: int, body: "str | bytes" = b""):
        self.status = status
        self.body = body


class _Request:
    "The request state the route functions read."

    def __init__(self, handler: BaseHTTPRequestHandler, query: "dict[str, str]"):
        self.headers = handler.headers
        self.query = query


def parse_qs(qs: str) -> "dict[str, str]":
    # parse_qsl keeps the last value per key.
    return dict(urllib.parse.parse_qsl(qs))


_HandlerFuncT = Callable[
    [...], "None|str|bytes|dict[str, Any]|HTTPResponse|Iterable[bytes]"
]


def handle_asserts(fn: _HandlerFuncT) -> _HandlerFuncT:
    "Convert assertion failures into HTTP 400s"

    @functools.wraps(fn)
    def wrapped(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except AssertionError as e:
            traceback.print_exc()
            return HTTPResponse(status=400, body=json.dumps({"error": list(e.args)}))

    return wrapped


def test_params(request: _Request) -> "dict[str, str]":
    return parse_qs(request.headers.get("X-MongoDB-HTTP-TestParams", ""))


def main():
    pass


@handle_asserts
def get_oauth2_token(request: _Request):
    api_version = request.query["api-version"]
    assert api_version == "2018-02-01", "Only api-version=2018-02-01 is supported"
    resource = request.query["resource"]
    assert (
        resource == "https://vault.azure.net"
    ), "Only https://vault.azure.net is supported"

    case = test_params(request).get("case")
    print("Case is:", case)
    if case == "404":
        return HTTPResponse(status=404)

    if case == "500":
        return HTTPResponse(status=500)

    if case == "bad-json":
        return b'{"key": }'

    if case == "empty-json":
        return b"{}"

    if case == "giant":
        return _gen_giant()

    if case == "slow":
        return _slow()

    assert case in (None, ""), f'Unknown HTTP test case "{case}"'

    return {
        "access_token": "magic-cookie",
        "expires_in": "70",
        "token_type": "Bearer",
        "resource": "https://vault.azure.net",
    }


def _gen_giant() -> Iterable[bytes]:
    "Generate a giant message"
    yield b'{ "item": ['
    for _ in range(1024 * 256):
        yield (
            b"null, null, null, null, null, null, null, null, null, null, "
            b"null, null, null, null, null, null, null, null, null, null, "
            b"null, null, null, null, null, null, null, null, null, null, "
            b"null, null, null, null, null, null, null, null, null, null, "
        )
    yield b" null ] }"
    yield b"\n"


def _slow() -> Iterable[bytes]:
    "Generate a very slow message"
    yield b'{ "item": ['
    for _ in range(1000):
        yield b"null, "
        time.sleep(1)
    yield b" null ] }"


class ImdsHandler(BaseHTTPRequestHandler):
    """Dispatches GETs to the route functions, rendering what they return."""

    def do_GET(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        request = _Request(self, dict(urllib.parse.parse_qsl(parsed.query)))
        try:
            if parsed.path == "/":
                response = main()
            elif parsed.path == "/metadata/identity/oauth2/token":
                response = get_oauth2_token(request)
            else:
                response = HTTPResponse(status=404)
        except KeyError:
            # A missing query parameter.
            response = HTTPResponse(status=500)
        self._send(response)

    def _send(self, response) -> None:
        "Render a route function's return value."
        if response is None:
            status, body, content_type = 200, b"", None
        elif isinstance(response, HTTPResponse):
            status, body, content_type = response.status, response.body, None
        elif isinstance(response, dict):
            status, body, content_type = 200, json.dumps(response), "application/json"
        elif isinstance(response, bytes):
            status, body, content_type = 200, response, "text/html; charset=UTF-8"
        else:  # a body iterable: stream it; the connection close delimits it
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=UTF-8")
            self.end_headers()
            for chunk in response:
                self.wfile.write(chunk)
                self.wfile.flush()
            return
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(status)
        if content_type:
            self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fake Azure IMDS server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    print(f"Fake Azure IMDS listening on http://{args.host}:{args.port}/")
    HTTPServer((args.host, args.port), ImdsHandler).serve_forever()
