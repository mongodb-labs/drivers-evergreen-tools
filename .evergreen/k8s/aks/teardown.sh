#!/usr/bin/env bash

set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -z "${DRIVER_NAME:-}" ]; then
    echo "Must set DRIVER_NAME!"
    exit 1
fi

if [ -f $SCRIPT_DIR/secrets-export.sh ]; then
  echo "Sourcing secrets"
  source $SCRIPT_DIR/secrets-export.sh
  export AZUREKMS_TENANTID=$AZUREOIDC_TENANTID
  export AZUREKMS_SECRET=$AZUREOIDC_SECRET
  export AZUREKMS_CLIENTID=$AZUREOIDC_CLIENTID
fi

# Delete an Azure VM. `az` is expected to be logged in.
if [ -z "${AZUREKMS_RESOURCEGROUP:-}" ] || \
   [ -z "${AZUREKMS_VMNAME:-}" ]; then
    echo "Please set the following required environment variables"
    echo " AZUREKMS_RESOURCEGROUP"
    echo " AZUREKMS_VMNAME"
    exit 1
fi

source $SCRIPT_DIR/cluster-env.sh
az aks get-credentials --overwrite-existing -n "${CLUSTER_NAME}" -g "${RESOURCE_GROUP}"
kubectl delete pod ${DRIVER_NAME}-test
