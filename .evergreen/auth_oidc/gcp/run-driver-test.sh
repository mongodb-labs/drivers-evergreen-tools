#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

# Check for inputs.
if [ -z "${GCPOIDC_DRIVERS_TAR_FILE:-}" ] || \
   [ -z "${GCPOIDC_TEST_CMD:-}" ]; then
    echo "Please set the following required environment variables"
    echo " GCPOIDC_DRIVERS_TAR_FILE"
    echo " GCPOIDC_TEST_CMD"
    exit 1
fi

# Read in the env variables.
source ./secrets-export.sh

# Set up variables.
export GCPKMS_KEYFILE=/tmp/testgcpkms_key_file.json

# Set up the remote driver checkout.
DRIVER_TARFILE_BASE=$(basename ${GCPOIDC_DRIVERS_TAR_FILE})
GCPKMS_SRC=${GCPOIDC_DRIVERS_TAR_FILE} \
GCPKMS_DST="~/" \
  $SCRIPT_DIR/../../csfle/gcpkms/copy-file.sh
echo "Copying files ... end"
echo "Untarring file ... begin"
GCPKMS_CMD="tar xf ${DRIVER_TARFILE_BASE}" \
  $SCRIPT_DIR/../../csfle/gcpkms/run-command.sh
echo "Untarring file ... end"

# Run the driver test.
GCPKMS_CMD="${GCPOIDC_TEST_CMD}" \
    $SCRIPT_DIR/../../csfle/gcpkms/run-command.sh
