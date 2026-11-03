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

# Tag the VM.
MONGODB_OWNER_TAG="${MONGODB_OWNER_TAG:-client-libraries-managers@mongodb.com}"
MONGODB_ENV_TAG="${MONGODB_ENV_TAG:-dev}"

AZUREKMS_VMNAME="vmname-$AZUREKMS_VMNAME_PREFIX-$RANDOM"

# Delete the VM and the resources created alongside it. Callers persist
# teardown metadata only after this script returns, so every failure after
# creation must clean up here. Defined before provisioning so a VM-create
# failure can call it. The NIC goes first: if the VM was never created, its
# delete option never fires and the attached NIC blocks the other deletes.
azurekms_cleanup_vm ()
{
    echo "Deleting VM ${AZUREKMS_VMNAME} and its supporting resources" 1>&2
    az vm delete --yes --resource-group "$AZUREKMS_RESOURCEGROUP" --name "$AZUREKMS_VMNAME" || true
    # The NIC is not named explicitly at create, so az names it <vmname>VMNic.
    az network nic delete --resource-group "$AZUREKMS_RESOURCEGROUP" --name "$AZUREKMS_VMNAME"VMNic || true
    az network public-ip delete --resource-group "$AZUREKMS_RESOURCEGROUP" --name "$AZUREKMS_VMNAME-PUBLIC-IP" || true
    az network nsg delete --resource-group "$AZUREKMS_RESOURCEGROUP" --name "$AZUREKMS_VMNAME-NSG" || true
    az network vnet delete --resource-group "$AZUREKMS_RESOURCEGROUP" --name "$AZUREKMS_VMNAME-VNET" || true
}

# Tag one supporting resource; on failure, clean up and abort.
azurekms_tag_resource ()
{
    local description=$1 id=$2
    if ! az tag create --resource-id "$id" \
        --tags "mongodb-owner=$MONGODB_OWNER_TAG" "mongodb-env=$MONGODB_ENV_TAG" \
        >/dev/null; then
        echo "Tagging the ${description} failed." 1>&2
        azurekms_cleanup_vm
        exit 1
    fi
}

# az vm create with no existing network implicitly creates an untagged one;
# create the network explicitly and tag it. Azure subnets cannot carry tags,
# so the vnet carries them. The created-at tag gives the janitor its grace
# period: the vnet exists before its VM does.
if ! az network vnet create \
    --resource-group "$AZUREKMS_RESOURCEGROUP" \
    --name "$AZUREKMS_VMNAME-VNET" \
    --subnet-name "$AZUREKMS_VMNAME-SUBNET" \
    --tags "mongodb-owner=$MONGODB_OWNER_TAG" "mongodb-env=$MONGODB_ENV_TAG" "created-at=$(date +%s)" \
    >/dev/null; then
    echo "Creating the virtual network failed." 1>&2
    exit 1
fi

echo "Creating a Virtual Machine ($AZUREKMS_VMNAME) ... begin"
# az vm create also creates a "nic" and "public IP" by default.
# Use --nic-delete-option 'Delete' to delete the NIC.
# Specify a name for the public IP to delete later.
# Specify a name for the Network Security Group (NSG) to delete later.
# Use --nsg-rule=NONE to remove default open SSH and RDP ports.
# Pipe to /dev/null to hide the output. The output includes tenantId.
if ! az vm create \
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
    --vnet-name "$AZUREKMS_VMNAME-VNET" \
    --subnet "$AZUREKMS_VMNAME-SUBNET" \
    --tags "mongodb-owner=$MONGODB_OWNER_TAG" "mongodb-env=$MONGODB_ENV_TAG" \
    >/dev/null; then
    echo "Creating the VM failed." 1>&2
    azurekms_cleanup_vm
    exit 1
fi

# az vm create --tags only reaches the VM itself; tag the implicitly created
# OS managed disk too. Each lookup and tag is guarded.
if ! OS_DISK_ID=$(az vm show \
    --resource-group "$AZUREKMS_RESOURCEGROUP" \
    --name "$AZUREKMS_VMNAME" \
    --query "storageProfile.osDisk.managedDisk.id" \
    --output tsv); then
    echo "Looking up the OS disk failed." 1>&2
    azurekms_cleanup_vm
    exit 1
fi
azurekms_tag_resource "OS disk" "$OS_DISK_ID"

# az vm create --tags reaches neither the NIC, public IP, nor NSG; tag those
# too.
if ! NIC_ID=$(az vm show \
    --resource-group "$AZUREKMS_RESOURCEGROUP" \
    --name "$AZUREKMS_VMNAME" \
    --query "networkProfile.networkInterfaces[0].id" \
    --output tsv); then
    echo "Looking up the NIC failed." 1>&2
    azurekms_cleanup_vm
    exit 1
fi
azurekms_tag_resource "NIC" "$NIC_ID"

if ! PUBLIC_IP_ID=$(az network public-ip show \
    --resource-group "$AZUREKMS_RESOURCEGROUP" \
    --name "$AZUREKMS_VMNAME-PUBLIC-IP" \
    --query id --output tsv); then
    echo "Looking up the public IP failed." 1>&2
    azurekms_cleanup_vm
    exit 1
fi
azurekms_tag_resource "public IP" "$PUBLIC_IP_ID"

if ! NSG_ID=$(az network nsg show \
    --resource-group "$AZUREKMS_RESOURCEGROUP" \
    --name "$AZUREKMS_VMNAME-NSG" \
    --query id --output tsv); then
    echo "Looking up the NSG failed." 1>&2
    azurekms_cleanup_vm
    exit 1
fi
azurekms_tag_resource "NSG" "$NSG_ID"

# If applicable, set the machine size.
if [ -n "${AZUREKMS_MACHINESIZE:-}" ]; then
    az vm resize -g "$AZUREKMS_RESOURCEGROUP" -n "$AZUREKMS_VMNAME" --size "$AZUREKMS_MACHINESIZE"
fi

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

# Verify tags when requested. verify_cloud_tags exits the
# sourcing shell, so on failure clean up here before exiting.
if [ -n "${VERIFY_MONGODB_TAGS:-}" ]; then
  if ! (
    . "$DRIVERS_TOOLS"/.evergreen/verify-tags.sh
    verify_cloud_tags "Azure VM ${AZUREKMS_VMNAME}" \
      "$(az vm show --resource-group "${AZUREKMS_RESOURCEGROUP}" --name "${AZUREKMS_VMNAME}" --query tags --output json)"
    verify_cloud_tags "Azure VM ${AZUREKMS_VMNAME} OS disk" \
      "$(az disk show --ids "${OS_DISK_ID}" --query tags --output json)"
    verify_cloud_tags "Azure VM ${AZUREKMS_VMNAME} NIC" \
      "$(az resource show --ids "${NIC_ID}" --query tags --output json)"
    verify_cloud_tags "Azure VM ${AZUREKMS_VMNAME} public IP" \
      "$(az resource show --ids "${PUBLIC_IP_ID}" --query tags --output json)"
    verify_cloud_tags "Azure VM ${AZUREKMS_VMNAME} NSG" \
      "$(az resource show --ids "${NSG_ID}" --query tags --output json)"
    verify_cloud_tags "Azure VM ${AZUREKMS_VMNAME} network" \
      "$(az network vnet show --resource-group "${AZUREKMS_RESOURCEGROUP}" --name "${AZUREKMS_VMNAME}-VNET" --query tags --output json)"
  ); then
    echo "Tag verification failed." 1>&2
    azurekms_cleanup_vm
    exit 1
  fi
fi
