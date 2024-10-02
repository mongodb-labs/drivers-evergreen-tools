#!/usr/bin/env bash

# set-ssh-ip.sh adds the current IP to an already-created VM.

set -o errexit
set -o pipefail
set -o nounset

# Get DRIVERS_TOOLS path.
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "$SCRIPT_DIR"/../../handle-paths.sh

VARLIST=(
    AZUREKMS_RESOURCEGROUP
    AZUREKMS_VMNAME
    AZUREKMS_PRIVATEKEYPATH
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in "${VARLIST[@]}"; do
  [[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

EXTERNAL_IP=$(curl -s http://whatismyip.akamai.com/)

echo "Adding current IP ($EXTERNAL_IP) to Azure Virtual Machine ... begin"
az network nsg rule update \
    --name "$AZUREKMS_VMNAME-nsg-rule" \
    --nsg-name "$AZUREKMS_VMNAME-nsg" \
    --resource-group "$AZUREKMS_RESOURCEGROUP" \
    --source-address-prefixes "$EXTERNAL_IP" > /dev/null

IP=$(az vm show --show-details --resource-group "$AZUREKMS_RESOURCEGROUP" --name "$AZUREKMS_VMNAME" --query publicIps -o tsv)

"$DRIVERS_TOOLS/.evergreen/retry-with-backoff.sh" ssh -n -o ConnectTimeout=10 -o StrictHostKeyChecking=no azureuser@"$IP" -i "$AZUREKMS_PRIVATEKEYPATH" "echo 'hi' > /dev/null"

echo "Adding current IP ($EXTERNAL_IP) to Azure Virtual Machine ... end"
