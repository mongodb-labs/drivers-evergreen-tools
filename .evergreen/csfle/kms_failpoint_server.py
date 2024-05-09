import argparse
import http.server
import json
import urllib
import ssl
import base64

"""
Example of setting a network failpoint:

$ curl -X POST localhost:3000
{"message": "ok"}

$ curl -X GET localhost:3000/set_failpoint/network/1
{"message": "failpoint set for type: 'network'"}

$ curl -X POST localhost:3000
curl: (52) Empty reply from server

$ curl -X POST localhost:3000
{"message": "ok"}

"""

# A new instance of Hander is created for every request, so these have to be global variables
failpoint_type = None
remaining_decrypt_fails = 0
remaining_network_fails = 0

fake_ciphertext = 'a' * 96
fake_plaintext = 'b' * 96

class HTTPServerWithTLS(http.server.HTTPServer):
    def __init__(self, server_address, Handler):
        super().__init__(server_address, Handler)
        self.socket = ssl.wrap_socket(
            self.socket,
            server_side=True,
            certfile='../x509gen/server.pem',
            ca_certs='../x509gen/ca.pem',
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
        return
    
    def do_GET(self):
        global failpoint_type
        global remaining_decrypt_fails
        global remaining_network_fails
        parts = urllib.parse.urlsplit(self.path)
        path = parts[2]
        if path.startswith("/set_failpoint"):
            parts = path.split('/')
            if parts[2] == 'network':
                remaining_network_fails = int(parts[3])
            elif parts[2] == 'http':
                remaining_decrypt_fails = int(parts[3])
            else:
                self.send_response(404)
                self.end_headers()
                return

            failpoint_type = parts[2]
            remaining_decrypt_fails = int(parts[3])
            print("Enabling failpoint for type: {}".format(failpoint_type))
            self._send_json(
                {"message": "failpoint set for type: '{}'".format(failpoint_type)}
            )
            return
        

    def do_POST(self):
        global remaining_decrypt_fails
        global remaining_network_fails
        global failpoint_type
        parts = urllib.parse.urlsplit(self.path)
        path = parts[2]

        # If a failpoint was set, fail the request.
        if remaining_network_fails > 0:
            remaining_network_fails -= 1
            raise Exception("mock network error")

        # No path for AWS
        if 'X-Amz-Target' in self.headers:
            print('AWS')
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

        # Azure auth path: /c01df00d-cafe-g00d-dea1-decea5sedbeef/oath2/v2.0/token
        if path.endswith("token"):
            return self._send_json({"access_token": "foo", "expires_in": 99999})
        # GCP encrypt
        elif path.endswith("encrypt"):
            return self._send_json({"ciphertext": base64.b64encode(fake_ciphertext.encode()).decode()})
        # GCP decrypt
        elif path.endswith("decrypt"):
            if remaining_decrypt_fails > 0:
                self._decrypt_fail()
                return
            return self._send_json({"plaintext": base64.b64encode(fake_plaintext.encode()).decode()})
        # Azure decrypt path: /keys/keyname//unwrapkey
        elif path.endswith("unwrapkey"):
            if remaining_decrypt_fails > 0:
                self._decrypt_fail()
                return
            return self._send_json({"value": base64.b64encode(fake_plaintext.encode()).decode()})
        # Azure encrypt path: /keys/keyname//wrapkey
        elif path.endswith("wrapkey"):
            return self._send_json({"value": base64.b64encode(fake_ciphertext.encode()).decode()})
        self._send_not_found()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='MongoDB mock KMS retry endpoint.')
    parser.add_argument('-p', '--port', type=int, default=9003, help="Port to listen on")
    args = parser.parse_args()

    server_address = ("localhost", args.port)
    httpd = HTTPServerWithTLS(server_address, Handler)
    print("Mock HTTP server listening on port " + str(server_address))
    httpd.serve_forever()
