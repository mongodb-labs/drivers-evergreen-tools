#!/usr/bin/env bash
#
# Entry point for Dockerfile for launching an oidc-enabled server.
#
set -eux
export MONGODB_VERSION=latest
export TOPOLOGY=servers
export ORCHESTRATION_FILE=auth-oidc.json
export DRIVERS_TOOLS=$HOME/drivers-evergreen-tools
export PROJECT_ORCHESTRATION_HOME=$DRIVERS_TOOLS/.evergreen/orchestration
export MONGO_ORCHESTRATION_HOME=$HOME
export NO_IPV6=${NO_IPV6:-""}

if [ ! -d $DRIVERS_TOOLS ]; then
    git clone https://github.com/mongodb-labs/drivers-evergreen-tools.git $DRIVERS_TOOLS
fi

cd $DRIVERS_TOOLS/.evergreen/auth_oidc
. ./activate-authoidcvenv.sh
python oidc_write_orchestration_azure.py

bash $DRIVERS_TOOLS/.evergreen/run-orchestration.sh
$DRIVERS_TOOLS/mongodb/bin/mongosh $DRIVERS_TOOLS/.evergreen/auth_oidc/setup_oidc_azure.js