#!/usr/bin/env python3
"""
Script for managing OIDC.
"""
import os
import json
import sys


HERE = os.path.abspath(os.path.dirname(__file__))
sys.path.insert(0, HERE)
from utils import get_secrets, MOCK_ENDPOINT, DEFAULT_CLIENT


def azure():
    client_id = os.environ['AZUREOIDC_USERNAME']
    tenant_id = os.environ['AZUREOIDC_TENANTID']
    app_id = os.environ['AZUREOIDC_APPID']
    auth_name_prefix = os.environ['AZUREOIDC_AUTHPREFIX']

    print("Bootstrapping OIDC config")

    # Write the oidc orchestration file.
    provider_info = {
        "authNamePrefix": auth_name_prefix,
        "issuer": f"https://sts.windows.net/{tenant_id}/",
        "clientId": client_id,
        "audience": f"api://{app_id}",
        "authorizationClaim": "groups",
        "supportsHumanFlows": False,
    }
    providers = json.dumps([provider_info], separators=(',',':'))

    data = {
        "id": "oidc-repl0",
        "auth_key": "secret",
        "login": client_id,
        "name": "mongod",
        "password": "pwd123",
        "procParams": {
            "ipv6": "NO_IPV6" not in os.environ,
            "bind_ip": "0.0.0.0,::1",
            "logappend": True,
            "port": 27017,
            "setParameter": {
                "enableTestCommands": 1,
                "authenticationMechanisms": "SCRAM-SHA-1,SCRAM-SHA-256,MONGODB-OIDC",
                "oidcIdentityProviders": providers
            }
        }
    }

    orch_file = os.path.abspath(os.path.join(HERE, '..', 'orchestration', 'configs', 'servers', 'auth-oidc.json'))
    with open(orch_file, 'w') as fid:
        json.dump(data, fid, indent=4)
    print(f"Wrote OIDC config to {orch_file}")

def main():
    print("Bootstrapping OIDC config")

    # Get the secrets.
    secrets = get_secrets()

    # Write the oidc orchestration file.
    provider1_info = {
        "authNamePrefix": "test1",
        "issuer": secrets['oidc_issuer_1_uri'],
        "clientId": DEFAULT_CLIENT,
        "audience": DEFAULT_CLIENT,
        "authorizationClaim": "foo",
        "requestScopes": ["fizz", "buzz"],
        "matchPattern": "test_user1"
    }
    provider2_info = {
        "authNamePrefix": "test2",
        "issuer": secrets['oidc_issuer_2_uri'],
        "clientId": DEFAULT_CLIENT,
        "audience": DEFAULT_CLIENT,
        "authorizationClaim": "bar",
        "supportsHumanFlows": False,
        "requestScopes": ["foo", "bar"],
    }

    providers = json.dumps([provider1_info, provider2_info], separators=(',',':'))

    data = {
        "id": "oidc-repl0",
        "auth_key": "secret",
        "login": "bob",
        "name": "mongod",
        "password": "pwd123",
        "members": [{
            "procParams": {
                "ipv6": "NO_IPV6" not in os.environ,
                "bind_ip": "0.0.0.0,::1",
                "logappend": True,
                "port": 27017,
                "setParameter": {
                    "enableTestCommands": 1,
                    "authenticationMechanisms": "SCRAM-SHA-1,SCRAM-SHA-256,MONGODB-OIDC",
                    "oidcIdentityProviders": providers
                }
            }
        }]
    }

    provider2_info['matchPattern'] = 'test_user2'
    del provider2_info['supportsHumanFlows']

    providers = [provider1_info, provider2_info]
    providers = json.dumps(providers, separators=(',',':'))
    data['members'].append({
        "procParams": {
            "ipv6": "NO_IPV6" not in os.environ,
            "bind_ip": "0.0.0.0,::1",
            "logappend": True,
            "port": 27018,
            "setParameter": {
                "enableTestCommands": 1,
                "authenticationMechanisms": "SCRAM-SHA-1,SCRAM-SHA-256,MONGODB-OIDC",
                "oidcIdentityProviders": providers
            }
        },
        "rsParams": {
            "priority": 0
        }
    })

    orch_file = os.path.abspath(os.path.join(HERE, '..', 'orchestration', 'configs', 'replica_sets', 'auth-oidc.json'))
    with open(orch_file, 'w') as fid:
        json.dump(data, fid, indent=4)
    print(f"Wrote OIDC config to {orch_file}")


if __name__ == '__main__':
    if '--azure' in sys.argv:
        azure()
    else:
        main()
