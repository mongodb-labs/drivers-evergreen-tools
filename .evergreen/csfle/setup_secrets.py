#!/usr/bin/env python3
"""
Set up encryption secrets.
"""

import base64
import json
import os
import time
import urllib.parse
import urllib.request

import boto3
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

os.environ["AWS_ACCESS_KEY_ID"] = os.environ["FLE_AWS_KEY"]
os.environ["AWS_SECRET_ACCESS_KEY"] = os.environ["FLE_AWS_SECRET"]
os.environ["AWS_DEFAULT_REGION"] = "us-east-1"
os.environ["AWS_SESSION_TOKEN"] = ""

print("Getting CSFLE temp creds")
client = boto3.client("sts")
credentials = client.get_session_token()["Credentials"]

azure_access_token = None
print("Getting Azure access token")
if all(
    key in os.environ
    for key in ["FLE_AZURE_CLIENTID", "FLE_AZURE_CLIENTSECRET", "FLE_AZURE_TENANTID"]
):
    # See: https://github.com/mongodb/libmongocrypt/blob/6d6bc38254a07bd47dbd0e665cffd67adf8746a9/kms-message/src/kms_azure_request.c#L37
    tenant_id = os.environ["FLE_AZURE_TENANTID"]
    client_id = os.environ["FLE_AZURE_CLIENTID"]
    client_secret = os.environ["FLE_AZURE_CLIENTSECRET"]

    url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
    body = urllib.parse.urlencode(
        {
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
            "scope": "https://vault.azure.net/.default",
        }
    ).encode()

    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )

    with urllib.request.urlopen(req) as resp:
        azure_access_token = json.loads(resp.read())["access_token"]
    print("Getting Azure access token...done")
else:
    print("Getting Azure access token...skipped: missing environment variables")

gcp_access_token = None
print("Getting GCP access token")
if all(key in os.environ for key in ["FLE_GCP_EMAIL", "FLE_GCP_PRIVATEKEY"]):
    # See: https://github.com/mongodb/libmongocrypt/blob/6d6bc38254a07bd47dbd0e665cffd67adf8746a9/kms-message/src/kms_gcp_request.c#L28
    email = os.environ["FLE_GCP_EMAIL"]
    private_key = os.environ["FLE_GCP_PRIVATEKEY"]
    scope = "https://www.googleapis.com/auth/cloudkms"

    now = int(time.time())

    def b64url(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).decode()

    # Build JWT header + payload:
    header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    payload = b64url(
        json.dumps(
            {
                "iss": email,
                "scope": scope,
                "aud": "https://oauth2.googleapis.com/token",
                "iat": now,
                "exp": now + 3600,
            }
        ).encode()
    )

    signing_input = f"{header}.{payload}".encode()

    # Sign with private key:
    key = serialization.load_pem_private_key(
        (
            "-----BEGIN PRIVATE KEY-----\n"
            + private_key
            + "\n-----END PRIVATE KEY-----\n"
        ).encode(),
        password=None,
    )
    signature = key.sign(signing_input, padding.PKCS1v15(), hashes.SHA256())
    jwt = f"{header}.{payload}.{b64url(signature)}"

    # Exchange JWT for access token:
    body = urllib.parse.urlencode(
        {
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": jwt,
        }
    ).encode()

    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )

    with urllib.request.urlopen(req) as resp:
        gcp_access_token = json.loads(resp.read())["access_token"]
    print("Getting GCP access token...done")
else:
    print("Getting GCP access token...skipped: missing environment variables")


with open("secrets-export.sh", "ab") as fid:
    fid.write(
        f'\nexport CSFLE_AWS_TEMP_ACCESS_KEY_ID="{credentials["AccessKeyId"]}"'.encode()
    )
    fid.write(
        f'\nexport CSFLE_AWS_TEMP_SECRET_ACCESS_KEY="{credentials["SecretAccessKey"]}"'.encode()
    )
    fid.write(
        f'\nexport CSFLE_AWS_TEMP_SESSION_TOKEN="{credentials["SessionToken"]}"'.encode()
    )
    if azure_access_token:
        fid.write(f'\nexport CSFLE_AZURE_ACCESS_TOKEN="{azure_access_token}"'.encode())

    if gcp_access_token:
        fid.write(f'\nexport CSFLE_GCP_ACCESS_TOKEN="{gcp_access_token}"'.encode())

    for key in [
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_DEFAULT_REGION",
        "AWS_SESSION_TOKEN",
        "CSFLE_TLS_CA_FILE",
        "CSFLE_TLS_CERT_FILE",
        "CSFLE_TLS_CLIENT_CERT_FILE",
    ]:
        fid.write(f'\nexport {key}="{os.environ[key]}"'.encode())
    fid.write(b"\n")

print("Getting CSFLE temp creds...done")
