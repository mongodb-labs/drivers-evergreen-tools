#!/usr/bin/env bash
#
# Get the set of OIDC tokens in the OIDC_TOKEN_DIR.
#
set -ex
HERE=$(dirname $0)
pushd $HERE

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
    AUTH_AWS="$HERE/../auth_aws"
    set -x
    echo "Getting oidc secrets"
    python $AUTH_AWS/setup_secrets.py drivers/oidc
    echo "Got secrets"
fi

source ./secrets-export.sh
python oidc_get_tokens.py
