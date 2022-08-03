"""
Mock a GCP Metadata Server. Returns a valid access_token.
"""

import http.server
import time
import base64
import json
import jwt
import requests
import textwrap
import os


def b64_to_b64url(b64):
    return b64.replace("+", "-").replace("/", "_").replace("=", "")


def dict_to_b64url(arg):
    as_json = json.dumps(arg).encode("utf8")
    as_b64 = base64.b64encode(as_json).decode("utf8")
    as_b64url = b64_to_b64url(as_b64)
    return as_b64url


def get_access_token():
    """
    Create a signed JSON Web Token (JWT) and obtain a GCP access token.
    """
    global private_key

    header = {"alg": "RS256", "typ": "JWT"}

    if "GOOGLE_APPLICATION_CREDENTIALS" not in os.environ:
        raise Exception(
            "please set GOOGLE_APPLICATION_CREDENTIALS environment variable to a JSON Service account key")
    creds = json.load(open(os.environ["GOOGLE_APPLICATION_CREDENTIALS"], "r"))
    private_key = creds["private_key"].encode("utf8")
    client_email = creds["client_email"]

    claims = {
        "iss": client_email,
        "aud": "https://oauth2.googleapis.com/token",
        "scope": "https://www.googleapis.com/auth/cloudkms",
        # Expiration can be at most one hour in the future. Let's say 30 minutes.
        "exp": int(time.time()) + 30 * 60,
        "iat": int(time.time())
    }

    assertion = jwt.encode(claims, private_key,
                           algorithm="RS256", headers=header)

    resp = requests.post(url="https://oauth2.googleapis.com/token", data={
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": assertion
    })

    if resp.status_code != 200:
        msg = textwrap.dedent(f"""
        Unexpected non-200 status.
        Got status {resp.status_code} on HTTP response:
            Headers:{resp.headers}
            Body:{resp.text}
        Sent request:
            Headers:{resp.request.headers}
            Body:{resp.request.text}
        """)
        raise Exception(msg)
    return resp.json()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        access_token = get_access_token()
        self.wfile.write(json.dumps(access_token).encode("utf8"))


def main():
    global private_key
    port = 5000
    server = http.server.HTTPServer(("localhost", port), Handler)
    print ("Listening on port {}".format(port))
    server.serve_forever()


if __name__ == "__main__":
    main()
