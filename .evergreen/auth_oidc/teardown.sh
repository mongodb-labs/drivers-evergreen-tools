#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Tear down the Atlas Cluster
source ./secrets-export.sh

export DRIVERS_ATLAS_PUBLIC_API_KEY=$OIDC_ATLAS_PUBLIC_API_KEY
export DRIVERS_ATLAS_PRIVATE_API_KEY=$OIDC_ATLAS_PRIVATE_API_KEY
export DRIVERS_ATLAS_GROUP_ID=$OIDC_ATLAS_GROUP_ID

if [ -n "${OIDC_IS_LOCAL:-}" ]; then
  echo "No teardown required!"
else
  bash ../atlas/teardown-atlas-cluster.sh
fi

popd
