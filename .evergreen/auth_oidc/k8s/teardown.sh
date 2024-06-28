#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

# Source the secrets.
source ./secrets-export.sh

# Tear down the Atlas Cluster
export DRIVERS_ATLAS_PUBLIC_API_KEY=$OIDC_ATLAS_PUBLIC_API_KEY
export DRIVERS_ATLAS_PRIVATE_API_KEY=$OIDC_ATLAS_PRIVATE_API_KEY
export DRIVERS_ATLAS_GROUP_ID=$OIDC_ATLAS_GROUP_ID
bash ../../atlas/teardown-atlas-cluster.sh

# Tear down the pod
bash ../../k8s/$K8S_VARIANT/teardown.sh

popd
