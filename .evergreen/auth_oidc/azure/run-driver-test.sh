#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

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
export AZUREKMS_PRIVATEKEYPATH=$SCRIPT_DIR/keyfile

# Permit SSH access from current IP.
"$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/set-ssh-ip.sh

# Set up the remote driver checkout.
DRIVER_TARFILE_BASE=$(basename ${AZUREOIDC_DRIVERS_TAR_FILE})
# shellcheck disable=SC2088
AZUREKMS_SRC=${AZUREOIDC_DRIVERS_TAR_FILE} \
AZUREKMS_DST="~/" \
  $SCRIPT_DIR/../../csfle/azurekms/copy-file.sh
echo "Copying files ... end"
echo "Untarring file ... begin"
AZUREKMS_CMD="tar xf ${DRIVER_TARFILE_BASE}" \
  $SCRIPT_DIR/../../csfle/azurekms/run-command.sh
echo "Untarring file ... end"

# Run the driver test.
AZUREKMS_CMD="${AZUREOIDC_TEST_CMD}" \
    $SCRIPT_DIR/../../csfle/azurekms/run-command.sh
