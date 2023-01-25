#!/usr/bin/env bash
#
# Bootstrapping file to launch a local oidc-enabled server and create
# OIDC tokens that can be used for local testing.  See README for
# prequisites and usage.
#
set -eux
DRIVERS_TOOLS=${DRIVERS_TOOLS:-$(readlink -f ../..)}
echo "Drivers tools: $DRIVERS_TOOLS"
export AWS_TOKEN_DIR=${AWS_TOKEN_DIR:-/tmp/tokens}

. ./activate_venv.sh
export NO_IPV6=true
python oidc_write_orchestration.py
python oidc_get_tokens.py
docker build -t oidc-test .
docker run -it -v ${DRIVERS_TOOLS}:/home/root/drivers-evergreen-tools -p 27017:27017 -p 27018:27018 -e HOME=/home/root oidc-test
