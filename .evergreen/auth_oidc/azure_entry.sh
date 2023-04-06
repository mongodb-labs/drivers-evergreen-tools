#!/usr/bin/env bash
#
# Entry point for Dockerfile for launching an oidc-enabled server.
#
set -eux
export MONGODB_VERSION=latest
export TOPOLOGY=server
export ORCHESTRATION_FILE=auth-oidc.json
export DRIVERS_TOOLS=$HOME/drivers-evergreen-tools
export PROJECT_ORCHESTRATION_HOME=$DRIVERS_TOOLS/.evergreen/orchestration
export MONGO_ORCHESTRATION_HOME=$HOME
export NO_IPV6=${NO_IPV6:-""}

if [ ! -d $DRIVERS_TOOLS ]; then
    git clone https://github.com/mongodb-labs/drivers-evergreen-tools.git $DRIVERS_TOOLS
fi

# TODO: add mongosh install from https://www.mongodb.com/docs/mongodb-shell/install/ ?

cd $DRIVERS_TOOLS/.evergreen/auth_oidc
. ./activate-authoidcvenv.sh
python oidc_write_orchestration_azure.py

bash $DRIVERS_TOOLS/.evergreen/run-orchestration.sh
$DRIVERS_TOOLS/mongodb/bin/mongosh $DRIVERS_TOOLS/.evergreen/auth_oidc/setup_oidc_azure.js

cd $HOME
if [ ! -d mongo-python-driver ]; then
    git clone --branch PYTHON-3460 https://github.com/blink1073/mongo-python-driver
fi
cd mongo-python-driver
python setup.py install --no_ext
pip install requests
cd ../drivers-evergreen-tools/.evergreen/auth_oidc
python3 test_azure.py