#!/usr/bin/env bash
#
# Bootstrapping file to launch a local oidc-enabled server and create
# OIDC tokens that can be used for local testing.  See README for
# prequisites and usage.
#
set -eux
if [[ -z "${AWS_ROLE_ARN}" ||  -z "${AWS_ACCESS_KEY_ID}" || -z "${AWS_SECRET_ACCESS_KEY}" ]]; then
    echo "Missing AWS credentials"
    exit 1
fi
export AWS_TOKEN_DIR=${AWS_TOKEN_DIR:-/tmp/tokens}

rm -rf authoidcvenv
. ./activate_venv.sh
python oidc_get_tokens.py