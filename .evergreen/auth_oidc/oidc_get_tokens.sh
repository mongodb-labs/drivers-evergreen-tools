#!/usr/bin/env bash
#
# Get the set of OIDC tokens in the OIDC_TOKEN_DIR.
#
set -ex
if [ -z "$OIDC_TOKEN_DIR" ]; then
    if [ "Windows_NT" = "$OS" ]; then
        export OIDC_TOKEN_DIR=C:/Temp/tokens
    else
        export OIDC_TOKEN_DIR=/tmp/tokens
    fi
fi
mkdir -p $OIDC_TOKEN_DIR
. ./activate-authoidcvenv.sh
python oidc_get_tokens.py
