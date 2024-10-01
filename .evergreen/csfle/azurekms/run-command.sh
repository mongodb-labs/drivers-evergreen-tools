#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

VARLIST=(
AZUREKMS_RESOURCEGROUP
AZUREKMS_VMNAME
AZUREKMS_PRIVATEKEYPATH
AZUREKMS_CMD
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in "${VARLIST[@]}"; do
  [[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

# Permit SSH access from current IP.
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
"$SCRIPT_DIR"/set-ssh-ip.sh

echo "Running '$AZUREKMS_CMD' on Azure Virtual Machine ... begin"
IP=$(az vm show --show-details --resource-group $AZUREKMS_RESOURCEGROUP --name $AZUREKMS_VMNAME --query publicIps -o tsv)
ssh -n -o StrictHostKeyChecking=no azureuser@$IP -i "$AZUREKMS_PRIVATEKEYPATH" "$AZUREKMS_CMD"
echo "Running '$AZUREKMS_CMD' on Azure Virtual Machine ... end"
