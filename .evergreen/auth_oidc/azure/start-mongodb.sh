#!/usr/bin/env bash
set -o errexit
set -o pipefail
# Do not error on unset variables. run-orchestration.sh accesses unset variables.

source env.sh

# Run Mongo Orchestration with OIDC Enabled
export MONGODB_VERSION=latest
export TOPOLOGY=server
export ORCHESTRATION_FILE=auth-oidc.json
export DRIVERS_TOOLS=$HOME/drivers-evergreen-tools
export PROJECT_ORCHESTRATION_HOME=$DRIVERS_TOOLS/.evergreen/orchestration
export MONGO_ORCHESTRATION_HOME=$HOME
export SKIP_LEGACY_SHELL=true
export NO_IPV6=${NO_IPV6:-""}

cd $DRIVERS_TOOLS/.evergreen/auth_oidc
. ./activate-authoidcvenv.sh
python oidc_write_orchestration.py --azure
bash oidc_get_tokens.sh

bash $DRIVERS_TOOLS/.evergreen/run-orchestration.sh
$DRIVERS_TOOLS/mongodb/bin/mongosh $DRIVERS_TOOLS/.evergreen/auth_oidc/setup_oidc.js
