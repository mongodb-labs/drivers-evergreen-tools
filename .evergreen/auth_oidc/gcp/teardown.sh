#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

# Source the secrets.
source ./secrets-export.sh

# Tear down the VM.  Do not let a failure prevent tearing down the cluster.
bash "$DRIVERS_TOOLS/.evergreen/csfle/gcpkms/delete-instance.sh" && delete_success="1" || delete_success="0"

# Tear down the Atlas Cluster
export DRIVERS_ATLAS_PUBLIC_API_KEY=$OIDC_ATLAS_PUBLIC_API_KEY
export DRIVERS_ATLAS_PRIVATE_API_KEY=$OIDC_ATLAS_PRIVATE_API_KEY
export DRIVERS_ATLAS_GROUP_ID=$OIDC_ATLAS_GROUP_ID
bash ../../atlas/teardown-atlas-cluster.sh

popd

[[ "${delete_success:?}" == "1" ]]
