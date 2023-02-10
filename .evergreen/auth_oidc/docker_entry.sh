#!/usr/bin/env bash
#
# Entry point for Dockerfile for launching an oidc-enabled server.
#
set -eux
export MONGODB_VERSION=latest
export TOPOLOGY=replica_set
export ORCHESTRATION_FILE=auth-oidc.json
export DRIVERS_TOOLS=$HOME/drivers-evergreen-tools
export PROJECT_ORCHESTRATION_HOME=$DRIVERS_TOOLS/.evergreen/orchestration
export MONGO_ORCHESTRATION_HOME=$HOME
export NO_IPV6=${NO_IPV6:-""}

if [ ! -d $DRIVERS_TOOLS ]; then
    git clone --branch DRIVERS-2415 https://github.com/blink1073/drivers-evergreen-tools.git $DRIVERS_TOOLS
fi

cd $DRIVERS_TOOLS/.evergreen/auth_oidc
. ./activate_venv.sh
python oidc_write_orchestration.py

bash $DRIVERS_TOOLS/.evergreen/run-orchestration.sh
sleep 2
$DRIVERS_TOOLS/mongodb/bin/mongo $DRIVERS_TOOLS/.evergreen/auth_oidc/setup_oidc.js
tail -f $MONGO_ORCHESTRATION_HOME/server.log