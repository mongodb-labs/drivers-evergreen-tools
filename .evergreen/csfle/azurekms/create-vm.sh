#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# Create an Azure VM. `az` is expected to be logged in.
if [ -z "${AZUREKMS_VMNAME_PREFIX:-}" ] || \
   [ -z "${AZUREKMS_RESOURCEGROUP:-}" ] || \
   [ -z "${AZUREKMS_IMAGE:-}" ] || \
   [ -z "${AZUREKMS_PUBLICKEYPATH:-}" ]; then
    echo "Please set the following required environment variables"
    echo " AZUREKMS_VMNAME_PREFIX to an identifier string no spaces (e.g. CDRIVER)"
    echo " AZUREKMS_RESOURCEGROUP"
    echo " AZUREKMS_IMAGE to the image (e.g. Debian)"
    echo " AZUREKMS_PUBLICKEYPATH to the path to the public SSH key"
    exit 1
fi

AZUREKMS_IDENTITY="${AZUREKMS_IDENTITY:-[system]}"
AZUREKMS_VMNAME="vmname-$AZUREKMS_VMNAME_PREFIX-$RANDOM"
echo "Creating a Virtual Machine ($AZUREKMS_VMNAME) ... begin"
# az vm create also creates a "nic" and "public IP" by default.
# Use --nic-delete-option 'Delete' to delete the NIC.
# Specify a name for the public IP to delete later.
# Specify a name for the Network Security Group (NSG) to delete later.
# Use --nsg-rule=NONE to remove default open SSH and RDP ports.
# Pipe to /dev/null to hide the output. The output includes tenantId.
az vm create \
    --resource-group "$AZUREKMS_RESOURCEGROUP" \
    --name "$AZUREKMS_VMNAME" \
    --image "$AZUREKMS_IMAGE" \
    --admin-username azureuser \
    --ssh-key-values "$AZUREKMS_PUBLICKEYPATH" \
    --public-ip-sku Standard \
    --nic-delete-option "Delete" \
    --data-disk-delete-option "Delete" \
    --os-disk-delete-option "Delete" \
    --public-ip-address "$AZUREKMS_VMNAME-PUBLIC-IP" \
    --nsg "$AZUREKMS_VMNAME-NSG" \
    --nsg-rule "NONE" \
    --assign-identity $AZUREKMS_IDENTITY \
    >/dev/null

if [ "$(uname -s)" = "Darwin" ]; then
    SHUTDOWN_TIME=$(date -u -v+1H +"%H%M")
else
    SHUTDOWN_TIME=$(date -u -d "$(date) + 1 hours" +"%H%M")
fi
az vm auto-shutdown -g $AZUREKMS_RESOURCEGROUP -n $AZUREKMS_VMNAME --time $SHUTDOWN_TIME

EXTERNAL_IP=$(curl -s http://whatismyip.akamai.com/)

# Add a network security group rule to permit SSH from current IP. This rule is updated with the current IP in "set-ssh-ip.sh" to permit SSH from different Evergreen hosts.
az network nsg rule create \
    --name "$AZUREKMS_VMNAME-nsg-rule" \
    --nsg-name "$AZUREKMS_VMNAME-nsg" \
    --priority 100 \
    --resource-group "$AZUREKMS_RESOURCEGROUP" \
    --destination-port-ranges 22 \
    --description "To allow SSH access" \
    --source-address-prefixes "$EXTERNAL_IP"

echo "Creating a Virtual Machine ($AZUREKMS_VMNAME) ... end"
