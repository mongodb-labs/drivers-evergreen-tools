#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# Read in the env variables.
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
. $DIR/../../handle-paths.sh
source $DIR/env.sh

export AZUREKMS_VMNAME=$AZUREOIDC_VMNAME
export AZUREKMS_RESOURCEGROUP=$AZUREOIDC_RESOURCEGROUP

"$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/delete-vm.sh
