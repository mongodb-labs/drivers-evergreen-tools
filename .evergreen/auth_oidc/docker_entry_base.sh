#!/usr/bin/env bash
#
# Entry point for Dockerfile for launching an oidc-enabled server.
#
set -eu
export ORCHESTRATION_FILE=auth-oidc.json

trap "rm -rf authoidcvenv" EXIT HUP

rm -f $DRIVERS_TOOLS/results.json
cd $DRIVERS_TOOLS/.evergreen/auth_oidc
rm -rf authoidcvenv
. ./activate-authoidcvenv.sh
python oidc_write_orchestration.py

bash /root/base-entrypoint.sh

/root/mongodb/bin/mongosh $DRIVERS_TOOLS/.evergreen/auth_oidc/setup_oidc.js

echo "Server started!"
