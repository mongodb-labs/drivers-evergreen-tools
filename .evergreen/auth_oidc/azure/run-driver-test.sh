#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

AZURE_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $AZURE_DIR

# Check for inputs.
if [ -z "${AZUREOIDC_DRIVERS_TAR_FILE:-}" ] || \
   [ -z "${AZUREOIDC_TEST_CMD:-}" ]; then
    echo "Please set the following required environment variables"
    echo " AZUREOIDC_DRIVERS_TAR_FILE"
    echo " AZUREOIDC_TEST_CMD"
    exit 1
fi

# Read in the env variables.
source ./env.sh

# Set up variables.
export AZUREKMS_RESOURCEGROUP=$AZUREOIDC_RESOURCEGROUP
export AZUREKMS_VMNAME=$AZUREOIDC_VMNAME
export AZUREKMS_PRIVATEKEYPATH=$AZURE_DIR/keyfile

# Set up the remote driver checkout.
DRIVER_TARFILE_BASE=$(basename ${AZUREOIDC_DRIVERS_TAR_FILE})
AZUREKMS_SRC=${AZUREOIDC_DRIVERS_TAR_FILE} \
AZUREKMS_DST="~/" \
  $AZURE_DIR/../../csfle/azurekms/copy-file.sh
echo "Copying files ... end"
echo "Untarring file ... begin"
AZUREKMS_CMD="tar xf ${DRIVER_TARFILE_BASE}" \
  $AZURE_DIR/../../csfle/azurekms/run-command.sh
echo "Untarring file ... end"

# Run the driver test.
AZUREKMS_CMD="${AZUREOIDC_TEST_CMD}" \
    $AZURE_DIR/../../csfle/azurekms/run-command.sh
