#!/usr/bin/env bash
#
# Get the set of OIDC tokens in the OIDC_TOKEN_DIR.
#
set -ex
DIR=$(dirname ${BASH_SOURCE:-$0})
. $DIR/../handle-paths.sh
pushd $DIR

if [ -z "$OIDC_TOKEN_DIR" ]; then
    export OIDC_TOKEN_DIR=/tmp/tokens
fi
if [ "Windows_NT" = "$OS" ]; then
    export OIDC_TOKEN_DIR=$(cygpath -m $OIDC_TOKEN_DIR)
fi
mkdir -p $OIDC_TOKEN_DIR

. ./activate-authoidcvenv.sh

if [ ! -f "./secrets-export.sh" ]; then
    AUTH_AWS="$DIR/../auth_aws"
    set -x
    echo "Getting oidc secrets"
    pushd $AUTH_AWS
    python ./setup_secrets.py drivers/oidc
    mv secrets-export.sh $DIR
    popd
    echo "Got secrets"
fi

source ./secrets-export.sh
python oidc_get_tokens.py
popd
