#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# Delete an Azure VM. `az` is expected to be logged in.
if [ -z "${AZUREKMS_RESOURCEGROUP:-}" ] || \
   [ -z "${AZUREKMS_VMNAME:-}" ]; then
    echo "Please set the following required environment variables"
    echo " AZUREKMS_RESOURCEGROUP"
    echo " AZUREKMS_VMNAME"
    exit 1
fi

if [ -n "${AZUREKMS_SCOPE}" ]; then
    echo "Deleting the role from the Virtual Machine $AZUREKMS_VMNAME ... begin"
    PRINCIPAL_ID=$(az vm show --show-details --resource-group "$AZUREKMS_RESOURCEGROUP" --name "$AZUREKMS_VMNAME" --query identity.principalId -o tsv)
    az role assignment delete \
        --assignee "$PRINCIPAL_ID" \
        --role "Key Vault Crypto User" \
        --scope "$AZUREKMS_SCOPE"
        -y \
        >/dev/null
    echo "Deleting the role from the Virtual Machine $AZUREKMS_VMNAME ... end"
fi

echo "Deleting Virtual Machine $AZUREKMS_VMNAME ... begin"
az vm delete \
    --resource-group "$AZUREKMS_RESOURCEGROUP" \
    --name "$AZUREKMS_VMNAME" \
    --yes
echo "Deleting Virtual Machine $AZUREKMS_VMNAME ... end"

echo "Delete public IP $AZUREKMS_VMNAME-PUBLIC-IP ... begin"
az network public-ip delete \
    --resource-group "$AZUREKMS_RESOURCEGROUP" \
    -n "$AZUREKMS_VMNAME-PUBLIC-IP"
echo "Delete public IP $AZUREKMS_VMNAME-PUBLIC-IP ... end"

echo "Delete Network Security Group $AZUREKMS_VMNAME-NSG ... begin"
az network nsg delete \
    --resource-group "$AZUREKMS_RESOURCEGROUP" \
    -n "$AZUREKMS_VMNAME-NSG"
echo "Delete Network Security Group $AZUREKMS_VMNAME-NSG ... end"
