#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# Read in the env variables.
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $DIR/env.sh

export AZUREKMS_VMNAME=$AZUREOIDC_VMNAME
export AZUREKMS_RESOURCEGROUP=$AZUREOIDC_RESOURCEGROUP

"$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/delete-vm.sh
