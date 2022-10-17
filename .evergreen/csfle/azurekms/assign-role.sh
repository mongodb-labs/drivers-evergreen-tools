#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# Assign a role to the Azure VM. `az` is expected to be logged in.
if [ -z "$AZUREKMS_RESOURCEGROUP" -o \
     -z "$AZUREKMS_VMNAME" -o \
     -z "$AZUREKMS_SCOPE" ]; then
    echo "Please set the following required environment variables"
    echo " AZUREKMS_RESOURCEGROUP"
    echo " AZUREKMS_VMNAME"
    echo " AZUREKMS_SCOPE"
    exit 1
fi

echo "Assigning a role to a Virtual Machine ... begin"
PRINCIPAL_ID=$(az vm show --show-details --resource-group "$AZUREKMS_RESOURCEGROUP" --name $AZUREKMS_VMNAME --query identity.principalId -o tsv)
# The scope was determined by going to the "Add role assignment" on the Key Vault.
az role assignment create \
    --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --scope "$AZUREKMS_SCOPE" \
    --role "Key Vault Crypto User" \
    >/dev/null
echo "Assigning a role to a Virtual Machine ... end"
