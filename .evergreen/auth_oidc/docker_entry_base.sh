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

$MONGODB_BINARIES/mongosh -f $DRIVERS_TOOLS/.evergreen/auth_oidc/setup_oidc.js "mongodb://127.0.0.1:27017/directConnection=true&serverSelectionTimeoutMS=10000"

echo "Server started!"
