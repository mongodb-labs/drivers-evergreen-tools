#!/usr/bin/env bash
#
# Entry point for Dockerfile for launching an oidc-enabled server.
#
set -eu
export ORCHESTRATION_FILE=auth-oidc.json

rm -f $DRIVERS_TOOLS/results.json
cd $DRIVERS_TOOLS/.evergreen/auth_oidc
. ./activate-authoidcvenv.sh
python oidc_write_orchestration.py

bash $DRIVERS_TOOLS/.evergreen/run-orchestration.sh
/root/mongosh $DRIVERS_TOOLS/.evergreen/auth_oidc/setup_oidc.js

# Change permissions of files we have created.
cd $DRIVERS_TOOLS
chown --reference=action.yml results.json
chmod --reference=action.yml results.json
chown --reference=action.yml uri.txt
chmod --reference=action.yml uri.txt

echo "Server started!"
