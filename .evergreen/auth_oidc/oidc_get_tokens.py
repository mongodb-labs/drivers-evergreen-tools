import os
import sys

HERE = os.path.abspath(os.path.dirname(__file__))
sys.path.insert(0, HERE)
from utils import get_secrets, get_id_token, DEFAULT_CLIENT, join
TOKEN_DIR = os.environ['OIDC_TOKEN_DIR'].replace(os.sep, '/')

def generate_tokens(config, base_name):
    os.makedirs(TOKEN_DIR, exist_ok=True)
    config['token_file'] = join(TOKEN_DIR, base_name)
    get_id_token(config)
    for i in range(2):
        config['token_file'] = join(TOKEN_DIR, f'{base_name}_{i+1}')
        get_id_token(config)
    config['token_file'] = join(TOKEN_DIR, f'{base_name}_expires')
    get_id_token(config, expires=60)


def main():
    secrets = get_secrets()
    config = {
        "issuer": secrets['oidc_issuer_1_uri'],
        "jwks_uri": secrets['oidc_jwks_uri'],
        'rsa_key': secrets['oidc_rsa_key'],
        'audience': DEFAULT_CLIENT,
        'client_id': DEFAULT_CLIENT,
        'client_secret': secrets['oidc_client_secret'],
        'username': f'test_user1@{secrets["oidc_domain"]}',
    }
    generate_tokens(config, 'test_user1')
    config['issuer'] = secrets['oidc_issuer_2_uri']
    config['username'] = f'test_user2@{secrets["oidc_domain"]}'
    generate_tokens(config, 'test_user2')
    config['username'] = 'test_machine'
    generate_tokens(config, 'test_machine')

    print(f"Wrote tokens to {TOKEN_DIR}")


if __name__ == '__main__':
    main()
