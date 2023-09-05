#!/usr/bin/env bash
#
# Get the set of OIDC tokens in the OIDC_TOKEN_DIR.
#
set -eux
export OIDC_TOKEN_DIR=${OIDC_TOKEN_DIR:-/tmp/tokens}
mkdir -p $OIDC_TOKEN_DIR
. ./activate-authoidcvenv.sh
python oidc_get_tokens.py
ls $OIDC_TOKEN_DIR
