"""
Script for handling OIDC credentials.
"""
import argparse
import base64
import os
import time
import uuid

from jwkest.jwk import RSAKey, import_rsa_key
from pyop.authz_state import AuthorizationState
from pyop.provider import Provider
from pyop.subject_identifier import HashBasedSubjectIdentifierFactory
from pyop.userinfo import Userinfo


class CustomSubjectIdentifierFactory(HashBasedSubjectIdentifierFactory):
    """
    Implements a hash based algorithm for creating a pairwise subject identifier.
    """
    def create_public_identifier(self, user_id):
        return user_id

    def create_pairwise_identifier(self, user_id, sector_identifier):
        return self._hash(sector_identifier + user_id)


HERE = os.path.abspath(os.path.dirname(__file__))
DEFAULT_CLIENT = "sts.amazonaws.com"
MOCK_ENDPOINT = "https://example.com"


def get_default_config():
    return {
        "issuer": os.getenv('IDP_ISSUER', ''),
        "jwks_uri": os.getenv('IDP_JWKS_URI', ''),
        'rsa_key': os.getenv('IDP_RSA_KEY', ''),
        'client_id': os.getenv("IDP_CLIENT_ID", DEFAULT_CLIENT),
        'client_secret': os.getenv("IDP_CLIENT_SECRET", uuid.uuid4().hex),
        'username': os.getenv("IDP_USERNAME", 'test_user'),
        'token_file': os.getenv('AWS_WEB_IDENTITY_TOKEN_FILE')
    }


def get_provider(config=None, expires=None):
    """Get a configured OIDC provider."""
    config = config or get_default_config()
    configuration_information = {
        'issuer': config['issuer'],
        'authorization_endpoint': MOCK_ENDPOINT,
        'jwks_uri': config['jwks_uri'],
        'token_endpoint': MOCK_ENDPOINT,
        'userinfo_endpoint': MOCK_ENDPOINT,
        'registration_endpoint': MOCK_ENDPOINT,
        'end_session_endpoint': MOCK_ENDPOINT,
        'scopes_supported': ['openid', 'profile'],
        'response_types_supported': ['code', 'code id_token', 'code token', 'code id_token token'],  # code and hybrid
        'response_modes_supported': ['query', 'fragment'],
        'grant_types_supported': ['authorization_code', 'implicit'],
        'subject_types_supported': ['public'],
        'token_endpoint_auth_methods_supported': ['client_secret_basic'],
        'claims_parameter_supported': True
    }

    userinfo_db = Userinfo({config['username']: {}})
    kid = '1549e0aef574d1c7bdd136c202b8d290580b165c'
    rsa_key = config['rsa_key']
    if rsa_key.endswith('='):
        rsa_key = base64.urlsafe_b64decode(rsa_key).decode('utf-8')
    signing_key = RSAKey(key=import_rsa_key(rsa_key), alg='RS256', use='sig', kid=kid)

    client_info = {
        'client_id': config['client_id'],
        'client_id_issued_at': int(time.time()),
        'client_secret': config['client_secret'],
        'redirect_uris': [MOCK_ENDPOINT],
        'response_types': ['code'],
        'client_secret_expires_at': 0  # never expires
    }
    clients = {config['client_id']: client_info}
    auth_state = AuthorizationState(CustomSubjectIdentifierFactory('salt'))
    expires = expires or 24*60*60
    return Provider(signing_key, configuration_information,
                    auth_state, clients, userinfo_db, id_token_lifetime=expires)


def get_id_token(config=None, expires=None):
    """Get a valid ID token."""
    config = config or get_default_config()
    provider = get_provider(config=config, expires=expires)
    client_id = config['client_id']
    client_secret = config['client_secret']
    response = provider.parse_authentication_request(f'response_type=code&client_id={client_id}&scope=openid&redirect_uri={MOCK_ENDPOINT}')
    resp = provider.authorize(response, config['username'])
    code = resp.to_dict()["code"]
    creds = f'{client_id}:{client_secret}'
    creds = base64.urlsafe_b64encode(creds.encode('utf-8')).decode('utf-8')
    headers = dict(Authorization=f'Basic {creds}')
    extra_claims = {'foo': ['readWrite'], 'bar': ['readWrite'] }
    response = provider.handle_token_request(f'grant_type=authorization_code&subject_type=public&code={code}&redirect_uri={MOCK_ENDPOINT}', headers, extra_id_token_claims=extra_claims)

    token = response["id_token"]
    if config['token_file']:
        with open(config['token_file'], 'w') as fid:
            print(f"Writing token file: {config['token_file']}")
            fid.write(token)
    return token


def get_jwks_data():
    """Get the jkws data for the jwks lambda endpoint."""
    return get_provider().jwks


def get_config_data():
    """Get the config data for the openid config lambda endpoint."""
    return get_provider().provider_configuration.to_dict()


def get_user_id():
    """Get the user id (sub) that will be used for authorization."""
    config = get_default_config()
    return get_provider(config).authz_state.get_subject_identifier('public', config['username'], "example.com")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument(dest='command', help="The command to run (config, jwks, token, user_id)")

    # Parse and print the results
    args = parser.parse_args()
    if args.command == 'jwks':
        print(get_jwks_data(), end='')
    elif args.command == 'config':
        print(get_config_data(), end='')
    elif args.command == 'token':
        print(get_id_token(), end='')
    elif args.command == 'user_id':
        print(get_user_id(), end='')
    else:
        raise ValueError('Command must be one of: (config, jwks, token, user_id)')
