#!/usr/bin/env bash
set -o errexit
set -o pipefail
# Do not error on unset variables. run-orchestration.sh accesses unset variables.

source env.sh

# Run Mongo Orchestration with OIDC Enabled
export MONGODB_VERSION=latest-stable
export TOPOLOGY=server
export ORCHESTRATION_FILE=auth-oidc.json
export DRIVERS_TOOLS=$HOME/drivers-evergreen-tools
export PROJECT_ORCHESTRATION_HOME=$DRIVERS_TOOLS/.evergreen/orchestration
export MONGO_ORCHESTRATION_HOME=$PROJECT_ORCHESTRATION_HOME
export SKIP_LEGACY_SHELL=true
export NO_IPV6=${NO_IPV6:-""}

cd $DRIVERS_TOOLS/.evergreen/auth_oidc
# The auth_oidc group is defined in the root pyproject.toml, so run from the
# root project context.
. $DRIVERS_TOOLS/.evergreen/ensure-uv.sh
ensure_uv || exit 1
uv run --project "$DRIVERS_TOOLS" --group auth_oidc python oidc_write_orchestration.py --azure

bash $DRIVERS_TOOLS/.evergreen/run-orchestration.sh
$DRIVERS_TOOLS/mongodb/bin/mongosh $DRIVERS_TOOLS/.evergreen/auth_oidc/setup_oidc.js
