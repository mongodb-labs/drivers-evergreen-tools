#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# Check for inputs.
if [ -z "${AZUREOIDC_DRIVERS_TAR_FILE:-}" ] || \
   [ -z "${AZUREOIDC_TEST_CMD:-}" ]; then
    echo "Please set the following required environment variables"
    echo " AZUREOIDC_DRIVERS_TAR_FILE"
    echo " AZUREOIDC_TEST_CMD"
    exit 1
fi

# Read in the env variables.
DIR=$(dirname $0)
source $DIR/env.sh

# Set up variables.
DRIVERS_TOOLS=$AZUREOIDC_DRIVERS_TOOLS
export AZUREKMS_RESOURCEGROUP=$AZUREOIDC_RESOURCEGROUP
export AZUREKMS_VMNAME=$AZUREOIDC_VMNAME
export AZUREKMS_PRIVATEKEYPATH=$DIR/keyfile

# Set up the remote driver checkout.
DRIVER_TARFILE_BASE=$(basename ${AZUREOIDC_DRIVERS_TAR_FILE})
AZUREKMS_SRC=${AZUREOIDC_DRIVERS_TAR_FILE} \
AZUREKMS_DST="~/" \
  $DRIVERS_TOOLS/.evergreen/csfle/azurekms/copy-file.sh
echo "Copying files ... end"
echo "Untarring file ... begin"
AZUREKMS_CMD="tar xf ${DRIVER_TARFILE_BASE}" \
  $DRIVERS_TOOLS/.evergreen/csfle/azurekms/run-command.sh
echo "Untarring file ... end"

# Run the driver test.
AZUREKMS_CMD="${AZUREOIDC_TEST_CMD}" \
    $DRIVERS_TOOLS/.evergreen/csfle/azurekms/run-command.sh