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
    client_id = os.environ['AZUREOIDC_TOKENCLIENT']
    tenant_id = os.environ['AZUREOIDC_TENANTID']
    app_id = os.environ['AZUREOIDC_CLIENTID']
    app_id2 = os.environ['AZUREOIDC_CLIENTID2']
    auth_name_prefix = os.environ['AZUREOIDC_AUTHPREFIX']
    auth_name_prefix2 = os.environ['AZUREOIDC_AUTHPREFIX2']

    print("Bootstrapping OIDC config")

    # Write the oidc orchestration file.
    provider_info = [{
        "authNamePrefix": auth_name_prefix,
        "issuer": f"https://sts.windows.net/{tenant_id}/",
        "clientId": client_id,
        "audience": f"api://{app_id}",
        "authorizationClaim": "groups",
        
    },{
        "authNamePrefix": auth_name_prefix2,
        "issuer": f"https://sts.windows.net/{tenant_id}/",
        "clientId": client_id,
        "audience": f"api://{app_id2}",
        "authorizationClaim": "groups",
        "matchPattern": auth_name_prefix2,
    }]
    providers = json.dumps(provider_info, separators=(',',':'))

    data = {
        "id": "oidc-repl0",
        "auth_key": "secret",
        "login": "bob",
        "name": "mongod",
        "password": "pwd123",
        "procParams": {
            "ipv6": "NO_IPV6" not in os.environ,
            "bind_ip": "0.0.0.0,::1",
            "logappend": True,
            "port": 27017,
            "setParameter": {
                "enableTestCommands": 1,
                "authenticationMechanisms": "SCRAM-SHA-256,MONGODB-OIDC",
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

    }
    providers = json.dumps([provider1_info], separators=(',',':'))

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
                    "authenticationMechanisms": "SCRAM-SHA-256,MONGODB-OIDC",
                    "oidcIdentityProviders": providers
                }
            }
        }]
    }

    provider1_info['matchPattern'] = "test_user1"
    provider2_info = {
        "authNamePrefix": "test2",
        "issuer": secrets['oidc_issuer_2_uri'],
        "clientId": DEFAULT_CLIENT,
        "audience": DEFAULT_CLIENT,
        "authorizationClaim": "bar",
        "matchPattern": "test_user2",
        "requestScopes": ["foo", "bar"],
    }
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
                "authenticationMechanisms": "SCRAM-SHA-256,MONGODB-OIDC",
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
