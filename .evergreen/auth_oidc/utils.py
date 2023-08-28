import json
import os
import sys

import boto3

HERE = os.path.abspath(os.path.dirname(__file__))
aws_lib = os.path.join(os.path.dirname(HERE), 'auth_aws', 'lib')
sys.path.insert(0, aws_lib)
from aws_handle_oidc_creds import get_id_token, MOCK_ENDPOINT
aws_root = os.path.join(os.path.dirname(HERE), 'auth_aws')
sys.path.insert(0, aws_root)
from setup_secrets import get_secrets as root_get_secrets

DEFAULT_CLIENT = "0oadp0hpl7q3UIehP297"


def get_secrets():
    """Get the driver secret values."""
    secrets = root_get_secrets(["drivers/oidc"], "us-east-1", None)[0]
    for key in list(secrets):
        secrets[key.lower()] = secrets[key]
    return secrets
