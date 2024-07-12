#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

# Source the secrets.
source $SCRIPT_DIR/secrets-export.sh

# If running locally, just exit
if [ "$OIDC_SERVER_TYPE" == "local" ]; then
  exit 0
fi

# Tear down the Atlas Cluster
export DRIVERS_ATLAS_PUBLIC_API_KEY=$OIDC_ATLAS_PUBLIC_API_KEY
export DRIVERS_ATLAS_PRIVATE_API_KEY=$OIDC_ATLAS_PRIVATE_API_KEY
export DRIVERS_ATLAS_GROUP_ID=$OIDC_ATLAS_GROUP_ID
bash $DRIVERS_TOOLS/.evergreen/atlas/teardown-atlas-cluster.sh
