#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# Copy a file to an Azure VM. `az` is expected to be logged in.
if [ -z "${AZUREKMS_RESOURCEGROUP:-}" ] || \
   [ -z "${AZUREKMS_VMNAME:-}" ] || \
   [ -z "${AZUREKMS_PRIVATEKEYPATH:-}" ] || \
   [ -z "${AZUREKMS_SRC:-}" ] || \
   [ -z "${AZUREKMS_DST:-}" ]; then
    echo "Please set the following required environment variables"
    echo " AZUREKMS_RESOURCEGROUP"
    echo " AZUREKMS_VMNAME"
    echo " AZUREKMS_PRIVATEKEYPATH"
    echo " AZUREKMS_SRC"
    echo " AZUREKMS_DST"
    exit 1
fi

# Permit SSH access from current IP.
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
"$SCRIPT_DIR"/set-ssh-ip.sh

echo "Copying file $AZUREKMS_SRC to Virtual Machine $AZUREKMS_DST ... begin"
IP=$(az vm show --show-details --resource-group "$AZUREKMS_RESOURCEGROUP" --name "$AZUREKMS_VMNAME" --query publicIps -o tsv)
# Use -o StrictHostKeyChecking=no to skip the prompt for known hosts.
# Use "-p" to preserve execute mode.
scp -o StrictHostKeyChecking=no -i "$AZUREKMS_PRIVATEKEYPATH" -p "$AZUREKMS_SRC"  azureuser@"$IP":"$AZUREKMS_DST"
echo "Copying file $AZUREKMS_SRC to Virtual Machine $AZUREKMS_DST ... end"
