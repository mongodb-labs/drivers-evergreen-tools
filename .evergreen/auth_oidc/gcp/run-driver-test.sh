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

echo "Copying files ... begin"
GCPKMS_SRC=$GCPOIDC_DRIVERS_TAR_FILE GCPKMS_DST=$GCPKMS_INSTANCENAME: $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/copy-file.sh
echo "Copying files ... end"

echo "Untarring file ... begin"
TARFILE_NAME=$(basename $GCPOIDC_DRIVERS_TAR_FILE)
GCPKMS_CMD="tar xf $TARFILE_NAME" $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/run-command.sh
echo "Untarring file ... end"

echo "Running test ... begin"
GPKSM_CMD=$GCPOIDC_TEST_CMD $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/run-command.sh
echo "Running test ... end"
