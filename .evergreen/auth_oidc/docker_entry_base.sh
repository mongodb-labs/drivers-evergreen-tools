#!/usr/bin/env bash
#
# Entry point for Dockerfile for launching an oidc-enabled server.
#
set -eu
export ORCHESTRATION_FILE=auth-oidc.json

cd $DRIVERS_TOOLS/.evergreen/auth_oidc
. ./activate-authoidcvenv.sh
python oidc_write_orchestration.py

bash $DRIVERS_TOOLS/.evergreen/run-orchestration.sh
$DRIVERS_TOOLS/mongodb/bin/mongosh $DRIVERS_TOOLS/.evergreen/auth_oidc/setup_oidc.js
tail -f $MONGO_ORCHESTRATION_HOME/server.log
