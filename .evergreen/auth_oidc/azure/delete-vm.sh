#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# Delete an Azure VM. `az` is expected to be logged in.
if [ -z "${AZUREOIDC_RESOURCEGROUP:-}" ] || \
    [ -z "${AZUREOIDC_DRIVERS_TOOLS:-}" ] || \
   [ -z "${AZUREOIDC_VMNAME:-}" ]; then
    echo "Please set the following required environment variables"
    echo " AZUREOIDC_RESOURCEGROUP"
    echo " AZUREOIDC_DRIVERS_TOOLS"
    echo " AZUREOIDC_VMNAME"
    exit 1
fi

export AZUREKMS_VMNAME=$AZUREOIDC_VMNAME
export AZUREKMS_RESOURCEGROUP=$AZUREOIDC_RESOURCEGROUP

"$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/delete-vm.sh
