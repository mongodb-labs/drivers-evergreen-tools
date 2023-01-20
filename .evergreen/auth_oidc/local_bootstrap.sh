#!/usr/bin/env bash
#
# Bootstrapping file to launch a local oidc-enabled server and create
# OIDC tokens that can be used for local testing.  See README for
# prequisites and usage.
#
export AWS_TOKEN_DIR=/tmp/tokens  
. ./activate_venv.sh
python oidc_bootstrap.py
docker build -t oidc-test .
docker run -it -v $(readlink -f ../..):/home/root/drivers-evergreen-tools -e USE_MULTIPLE_PRINCIPALS=$USE_MULTIPLE_PRINCIPALS oidc-test
