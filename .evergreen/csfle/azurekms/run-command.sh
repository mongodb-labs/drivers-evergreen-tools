#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

if [ -z "$AZUREKMS_RESOURCEGROUP" -o \
     -z "$AZUREKMS_VMNAME" -o \
     -z "$AZUREKMS_PRIVATEKEYPATH" -o \
     -z "$AZUREKMS_CMD" ]; then
    echo "Please set the following required environment variables"
    echo " AZUREKMS_RESOURCEGROUP"
    echo " AZUREKMS_VMNAME"
    echo " AZUREKMS_PRIVATEKEYPATH"
    echo " AZUREKMS_CMD"
    exit 1
fi

echo "Running '$AZUREKMS_CMD' on Azure Virtual Machine ... begin"
IP=$(az vm show --show-details --resource-group $AZUREKMS_RESOURCEGROUP --name $AZUREKMS_VMNAME --query publicIps -o tsv)
ssh -o StrictHostKeyChecking=no azureuser@$IP -i "$AZUREKMS_PRIVATEKEYPATH" "$AZUREKMS_CMD"
echo "Running '$AZUREKMS_CMD' on Azure Virtual Machine ... end"
