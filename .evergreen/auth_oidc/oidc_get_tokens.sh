#!/usr/bin/env bash
#
# Get the set of OIDC tokens in the OIDC_TOKEN_DIR.
#
set -ex
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

if [ -z "$OIDC_TOKEN_DIR" ]; then
    export OIDC_TOKEN_DIR=/tmp/tokens
fi
if [ "Windows_NT" = "$OS" ]; then
    export OIDC_TOKEN_DIR=$(cygpath -m $OIDC_TOKEN_DIR)
fi
mkdir -p $OIDC_TOKEN_DIR

pushd $SCRIPT_DIR
. ./activate-authoidcvenv.sh
popd

if [ ! -f "./secrets-export.sh" ]; then
    set -x
    echo "Getting oidc secrets"
    python $SCRIPT_DIR/../auth_aws/setup_secrets.py drivers/oidc
    echo "Got secrets"
fi

source ./secrets-export.sh
python $SCRIPT_DIR/oidc_get_tokens.py
