#!/usr/bin/env python3
"""
Script for managing OIDC on azure.
"""
import os
import json
import sys


HERE = os.path.abspath(os.path.dirname(__file__))
sys.path.insert(0, HERE)

client_id = os.environ['AZUREOIDC_CLIENTID']
tenant_id = os.environ['AZUREKMS_TENANTID']
app_id = os.environ['AZUREOIDC_APPID']


def main():
    print("Bootstrapping OIDC config")


    # Write the oidc orchestration file.
    provider_info = {
        "JWKSUri": "https://login.windows.net/common/discovery/keys",
        "authNamePrefix": "OIDC_test",
        "issuer": f"https://sts.windows.net/{tenant_id}",
        "clientId": client_id,
        "audience": app_id,
        "authorizationClaim": "foo",

    }
    providers = json.dumps([provider_info], separators=(',',':'))

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
                    "oidcIdentityProviders": providers,
                    "featureFlagOIDC": True
                }
            }
        }]
    }

    orch_file = os.path.abspath(os.path.join(HERE, '..', 'orchestration', 'configs', 'server', 'auth-oidc.json'))
    with open(orch_file, 'w') as fid:
        json.dump(data, fid, indent=4)


if __name__ == '__main__':
    main()
