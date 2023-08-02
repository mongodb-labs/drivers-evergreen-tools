import os
import sys

HERE = os.path.abspath(os.path.dirname(__file__))
sys.path.insert(0, HERE)
from utils import get_secrets, get_id_token, DEFAULT_CLIENT


def main():
    token_dir = os.environ['OIDC_TOKEN_DIR']
    os.makedirs(token_dir, exist_ok=True)
    config = {
        "issuer": os.getenv('oidc_issuer_1_uri'.upper()),
        "jwks_uri": os.getenv('oidc_jwks_uri'.upper()),
        'rsa_key': os.getenv('oidc_rsa_key'.upper()),
        'audience': DEFAULT_CLIENT,
        'client_id': DEFAULT_CLIENT,
        'client_secret': os.getenv('oidc_client_secret'),
        'username': 'test_user1',
        'token_file': os.path.join(token_dir, 'test_user1')
    }
    get_id_token(config)
    for i in range(2):
        config['token_file'] = os.path.join(token_dir, f'test_user1_{i+1}')
        get_id_token(config)
    config['issuer'] = os.getenv('oidc_issuer_2_uri'.upper())
    config['username'] = 'test_user2'
    config['token_file'] = os.path.join(token_dir, 'test_user2')
    get_id_token(config)
    for i in range(2):
        config['token_file'] = os.path.join(token_dir, f'test_user2_{i+1}')
        get_id_token(config)
    config['issuer'] = os.getenv('oidc_issuer_1_uri'.upper())
    config['username'] = 'test_user1'
    config['token_file'] = os.path.join(token_dir, 'test_user1_expires')
    get_id_token(config, expires=60)

    print(f"Wrote tokens to {token_dir}")


if __name__ == '__main__':
    main()