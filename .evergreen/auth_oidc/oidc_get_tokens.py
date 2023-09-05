import os
import sys

HERE = os.path.abspath(os.path.dirname(__file__))
sys.path.insert(0, HERE)
from utils import get_secrets, get_id_token, DEFAULT_CLIENT, join


def main():
    token_dir = os.environ['OIDC_TOKEN_DIR'].replace(os.sep, '/')
    os.makedirs(token_dir, exist_ok=True)
    secrets = get_secrets()
    config = {
        "issuer": secrets['oidc_issuer_1_uri'],
        "jwks_uri": secrets['oidc_jwks_uri'],
        'rsa_key': secrets['oidc_rsa_key'],
        'audience': DEFAULT_CLIENT,
        'client_id': DEFAULT_CLIENT,
        'client_secret': secrets['oidc_client_secret'],
        'username': 'test_user1',
        'token_file': join(token_dir, 'test_user1')
    }
    get_id_token(config)
    for i in range(2):
        config['token_file'] = join(token_dir, f'test_user1_{i+1}')
        get_id_token(config)
    config['issuer'] = secrets['oidc_issuer_2_uri']
    config['username'] = 'test_user2'
    config['token_file'] = join(token_dir, 'test_user2')
    get_id_token(config)
    for i in range(2):
        config['token_file'] = join(token_dir, f'test_user2_{i+1}')
        get_id_token(config)
    config['issuer'] = secrets['oidc_issuer_1_uri']
    config['username'] = 'test_user1'
    config['token_file'] =  join(token_dir, 'test_user1_expires')
    get_id_token(config, expires=60)

    print(f"Wrote tokens to {token_dir}")


if __name__ == '__main__':
    main()
