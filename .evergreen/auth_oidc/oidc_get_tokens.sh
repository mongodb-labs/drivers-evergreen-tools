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

if [ ! -f "./secrets-export.sh" ]; then
    . $SCRIPT_DIR/setup-secrets.sh
fi

python ./oidc_get_tokens.py
