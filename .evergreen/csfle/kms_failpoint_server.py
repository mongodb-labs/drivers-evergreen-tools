"""
A mock KMS (Azure, AWS, GCP) server with failpoints for testing error scenarios.

Example of setting a network failpoint:

python kms_failpoint_server.py -p 3000 --no-tls &

$ curl -X POST localhost:3000/keys/{key-name}/{key-version}/unwrapkey
{"plaintext": "YmJi..."}

$ curl -X POST localhost:3000/set_failpoint/network -d '{"count": 1}'
{"message": "failpoint set for type: 'network'"}

$ curl -X POST localhost:3000/keys/{key-name}/{key-version}/unwrapkey
curl: (52) Empty reply from server

$ curl -X POST localhost:3000/keys/{key-name}/{key-version}/unwrapkey
{"plaintext": "YmJi..."}
"""

import argparse
import http.server
import json
import urllib
import ssl
import base64
import os
from pathlib import PurePosixPath

# A new instance of Handler is created for every request, so these have to be global variables
remaining_decrypt_fails = 0
remaining_network_fails = 0

fake_ciphertext = 'a' * 96
fake_plaintext = 'b' * 96

class HTTPServerWithTLS(http.server.HTTPServer):
    def __init__(self, server_address, Handler, use_tls=True):
        super().__init__(server_address, Handler)

        if use_tls:
            server_dir = os.path.dirname(__file__)
            cert_file = os.path.join(server_dir, "..", "x509gen", "server.pem")
            ca_file = os.path.join(server_dir, "..", "x509gen", "ca.pem")
            self.socket = ssl.wrap_socket(
                self.socket,
                server_side=True,
                certfile=cert_file,
                ca_certs=ca_file,
                ssl_version=ssl.PROTOCOL_TLS
            )


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send_json(self, data: dict):
        data_json: bytes = json.dumps(data).encode("utf8")
        self.send_response(http.HTTPStatus.OK)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(data_json))
        self.end_headers()
        self.wfile.write(data_json)

    def _send_not_found(self):
        self.send_response(http.HTTPStatus.NOT_FOUND)
        msg = "Not found".encode("utf8")
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", len(msg))
        self.end_headers()
        self.wfile.write(msg)

    def _decrypt_fail(self):
        global remaining_decrypt_fails
        remaining_decrypt_fails -= 1
        self.send_response(429)
    def do_POST(self):
        global remaining_decrypt_fails
        global remaining_network_fails
        parts = urllib.parse.urlsplit(self.path)
        path = PurePosixPath(parts.path)

        if path.match("/set_failpoint/*"):
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode('utf-8'))

            failpoint_type = path.parts[-1]
            if failpoint_type == 'network':
                remaining_network_fails = data['count']
            elif failpoint_type == 'http':
                remaining_decrypt_fails = data['count']
            else:
                self._send_not_found()
                return
            print("Enabling failpoint for type: {}".format(failpoint_type))
            self._send_json(
                {"message": "failpoint set for type: '{}'".format(failpoint_type)}
            )
            return

        # If a failpoint was set, fail the request.
        if remaining_network_fails > 0:
            remaining_network_fails -= 1
            raise Exception("mock network error")

        # No path for AWS
        if 'X-Amz-Target' in self.headers and str(path) == "/":
            aws_op = self.headers['X-Amz-Target']
            if aws_op == "TrentService.Encrypt":
                self._send_json({"CiphertextBlob": base64.b64encode(fake_ciphertext.encode()).decode()})
                return
            elif aws_op == "TrentService.Decrypt":
                if remaining_decrypt_fails > 0:
                    self._decrypt_fail()
                    return
                self._send_json({"Plaintext": base64.b64encode(fake_plaintext.encode()).decode()})
                return
            else:
                self._send_not_found()
                return

        # Azure auth path: /c01df00d-cafe-g00d-dea1-decea5sedbeef/oauth2/v2.0/token
        if path.match("*token"):
            return self._send_json({"access_token": "foo", "expires_in": 99999})
        # GCP encrypt path: /v1/projects/{project}/locations/{location}/keyRings/{key-ring}/cryptoKeys/{key}:encrypt
        elif path.match("*encrypt"):
            return self._send_json({"ciphertext": base64.b64encode(fake_ciphertext.encode()).decode()})
        # GCP decrypt path: /v1/projects/{project}/locations/{location}/keyRings/{key-ring}/cryptoKeys/{key}:decrypt
        elif path.match("*decrypt"):
            if remaining_decrypt_fails > 0:
                self._decrypt_fail()
                return
            return self._send_json({"plaintext": base64.b64encode(fake_plaintext.encode()).decode()})
        # Azure decrypt path: /keys/{key-name}/{key-version}/unwrapkey
        elif path.match("*unwrapkey"):
            if remaining_decrypt_fails > 0:
                self._decrypt_fail()
                return
            return self._send_json({"value": base64.b64encode(fake_plaintext.encode()).decode()})
        # Azure encrypt path: /keys/{key-name}/{key-version}/wrapkey
        elif path.match("*wrapkey"):
            return self._send_json({"value": base64.b64encode(fake_ciphertext.encode()).decode()})
        self._send_not_found()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='MongoDB mock KMS retry endpoint.')
    parser.add_argument('-p', '--port', type=int, default=9003, help="Port to listen on")
    parser.add_argument('--no-tls', action='store_true', help="Disable TLS")
    args = parser.parse_args()

    server_address = ("localhost", args.port)
    httpd = HTTPServerWithTLS(server_address, Handler, not args.no_tls)
    print("Mock HTTP server listening on port " + str(server_address))
    httpd.serve_forever()
