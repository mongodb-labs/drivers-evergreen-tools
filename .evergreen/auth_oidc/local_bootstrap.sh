#!/usr/bin/env bash
#
# Bootstrapping file to launch a local oidc-enabled server and create
# OIDC tokens that can be used for local testing.  See README for
# prequisites and usage.
#
set -eux
export AWS_TOKEN_DIR=/tmp/tokens  
. ./activate_venv.sh
export NO_IPV6=true
python oidc_bootstrap.py
docker build -t oidc-test .
USE_MULTIPLE_PRINCIPALS=${USE_MULTIPLE_PRINCIPALS:-false}
docker run -it -v $(readlink -f ../..):/home/root/drivers-evergreen-tools -e USE_MULTIPLE_PRINCIPALS=$USE_MULTIPLE_PRINCIPALS  -p 27017:27017 oidc-test
