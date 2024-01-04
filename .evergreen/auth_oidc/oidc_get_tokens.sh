#!/usr/bin/env bash
#
# Get the set of OIDC tokens in the OIDC_TOKEN_DIR.
#
set -ex
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

if [ -z "$OIDC_TOKEN_DIR" ]; then
    if [ "Windows_NT" = "$OS" ]; then
        export OIDC_TOKEN_DIR=C:/Temp/tokens
    else
        export OIDC_TOKEN_DIR=/tmp/tokens
    fi
fi
mkdir -p $OIDC_TOKEN_DIR
. ./activate-authoidcvenv.sh

if [ ! -f "./secrets-export.sh" ]; then
    AUTH_AWS="$SCRIPT_DIR/../auth_aws"
    set -x
    echo "Getting oidc secrets"
    pushd $AUTH_AWS
    python ./setup_secrets.py drivers/oidc
    mv secrets-export.sh $SCRIPT_DIR
    popd
    echo "Got secrets"
fi

source ./secrets-export.sh
python oidc_get_tokens.py
popd
