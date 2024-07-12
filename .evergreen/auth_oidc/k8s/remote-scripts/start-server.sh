#!/usr/bin/env bash
set -eu

# Start an OIDC-enabled server.
SCRIPT_DIR=$(realpath $(dirname ${BASH_SOURCE[0]}))
cd $SCRIPT_DIR
source secrets-export.sh

mkdir drivers-tools
tar -xf drivers-tools.tgz -C drivers-tools

export ORCHESTRATION_FILE=auth-oidc.json
export DRIVERS_TOOLS=$SCRIPT_DIR/drivers-tools
export PROJECT_ORCHESTRATION_HOME=$DRIVERS_TOOLS/.evergreen/orchestration
export MONGO_ORCHESTRATION_HOME=$DRIVERS_TOOLS/.evergreen/orchestration
export MONGODB_BINARIES=$DRIVERS_TOOLS/mongodb/bin
export K8S_OIDC_AUTHPREFIX=auth_prefix
export MONGODB_VERSION=8.0

OIDC_IDENTITY_PROVIDERS="[{\\\"issuer\\\":\\\"$K8S_OIDC_ISSUER\\\",\\\"audience\\\":\\\"$K8S_OIDC_AUDIENCE\\\",\\\"authNamePrefix\\\":\\\"$K8S_OIDC_AUTHPREFIX\\\",\\\"principalName\\\":\\\"sub\\\",\\\"logClaims\\\":[\\\"aud\\\",\\\"sub\\\"],\\\"JWKSPollSecs\\\":86400,\\\"useAuthorizationClaim\\\":false,\\\"supportsHumanFlows\\\":false}]"

cat <<EOF >> $MONGO_ORCHESTRATION_HOME/configs/servers/$ORCHESTRATION_FILE
{
    "id": "oidc",
    "auth_key": "secret",
    "login": "bob",
    "name": "mongod",
    "password": "pwd123",
    "procParams": {
        "ipv6": false,
        "bind_ip": "0.0.0.0,::1",
        "logappend": true,
        "port": 27017,
        "setParameter": {
            "enableTestCommands": 1,
            "authenticationMechanisms": "SCRAM-SHA-1,SCRAM-SHA-256,MONGODB-OIDC",
            "oidcIdentityProviders": "$OIDC_IDENTITY_PROVIDERS"
        }
    }
}
EOF

cd $DRIVERS_TOOLS/.evergreen
apt-get -yqq install curl lsof
bash run-orchestration.sh

$MONGODB_BINARIES/mongosh -f $SCRIPT_DIR/setup_oidc.js "mongodb://127.0.0.1:27017/directConnection=true&serverSelectionTimeoutMS=10000"
