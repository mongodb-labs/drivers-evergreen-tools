#!/usr/bin/env python3
"""
Script for managing OIDC.
"""
import os
import boto3
import json
import uuid
import sys


HERE = os.path.abspath(os.path.dirname(__file__))
sys.path.insert(0, HERE)
from aws_handle_oidc_creds import get_id_token, DEFAULT_CLIENT, MOCK_ENDPOINT


def get_secrets():
    """Get the driver secret values."""
    # Create a session using the given creds
    session = boto3.Session(aws_access_key_id=os.environ['AWS_ACCESS_KEY_ID'], aws_secret_access_key=os.environ['AWS_SECRET_ACCESS_KEY'], aws_session_token=os.environ['AWS_SESSION_TOKEN'])
    client = session.client(service_name='secretsmanager', region_name='us-west-2')
    try:
        get_secret_value_response = client.get_secret_value(
            SecretId='drivers/test'
        )
    except Exception as e:
        # For a list of exceptions thrown, see
        # https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
        raise e

    # Decrypts secret using the associated KMS key.
    return json.loads(get_secret_value_response['SecretString'])


def main():
    # Get the secrets.
    secrets = get_secrets()

    # Write the oidc orchestration file.
    provider_info = [{
        "authURL": MOCK_ENDPOINT,
        "tokenURL": MOCK_ENDPOINT,
        "JWKS": secrets['oidc_jwks_uri'],
        "authNamePrefix": "test1",
        "issuer": secrets['oidc_issuer_1_uri'],
        "clientId": DEFAULT_CLIENT,
        "audience": DEFAULT_CLIENT,
        "authorizationClaim": "foo",
        "matchPattern": "test1",
    }]
    if os.getenv('USE_MULTIPLE_PRINCIPALS', '').lower() == "true":
        provider_info.append({
            "deviceAuthURL": MOCK_ENDPOINT,
            "JWKS": secrets['oidc_jwks_uri'],
            "authNamePrefix": "test2",
            "issuer": secrets['oidc_issuer_2_uri'],
            "clientId": DEFAULT_CLIENT,
            "audience": DEFAULT_CLIENT,
            "authorizationClaim": "bar",
            "matchPattern": "test2",
        })
    else:
        del provider_info[0]['matchPattern']

    data = {
        "id": "standalone-oidc",
        "auth_key": "secret",
        "login": "bob",
        "name": "mongod",
        "password": "pwd123",
        "procParams": {
            "ipv6": True,
            "bind_ip": "127.0.0.1,::1",
            "logappend": True,
            "port": 27017,
            "setParameter": {
                "enableTestCommands": 1,
                "authenticationMechanisms": "SCRAM-SHA-256,MONGODB-OIDC",
                "oidcIdentityProviders": json.dumps(provider_info),
                "featureFlagOIDC": True
            }
        }
    }
    orch_file = os.path.abspath(os.path.join(HERE, '..', '..', 'orchestration', 'configs', 'servers', 'auth-oidc.json'))
    with open(orch_file, 'w') as fid:
        json.dump(data, fid, indent=4)

    # Write the token files.
    token_dir = os.environ['AWS_TOKEN_DIR']
    os.makedirs(token_dir, exist_ok=True)
    config = {
        "issuer": secrets['oidc_issuer_1_uri'],
        "jwks_uri": secrets['oidc_jwks_uri'],
        'rsa_key': secrets['oidc_rsa_key'],
        'audience': DEFAULT_CLIENT,
        'client_id': DEFAULT_CLIENT,
        'client_secret':secrets['oidc_client_secret'],
        'username': 'test_user',
        'token_file': os.path.join(token_dir, 'test1')
    }
    get_id_token(config)
    config['issuer'] = secrets['oidc_issuer_2_uri']
    config['token_file'] = os.path.join(token_dir, 'test2')
    get_id_token(config)


if __name__ == '__main__':
    main()
