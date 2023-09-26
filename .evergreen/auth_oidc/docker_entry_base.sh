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

bash $DRIVERS_TOOLS/.evergreen/run-orchestration.sh
/root/mongodb/bin/mongosh $DRIVERS_TOOLS/.evergreen/auth_oidc/setup_oidc.js

# Change permissions of files we have created.
cd $DRIVERS_TOOLS
files="results.json uri.txt .evergreen/mongo_crypt_v1.so"
for fname in $files; do
    chown --reference=action.yml $fname
    chmod --reference=action.yml $fname
fi

echo "Server started!"
