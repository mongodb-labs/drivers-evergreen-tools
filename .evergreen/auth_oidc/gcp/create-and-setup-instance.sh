#!/usr/bin/env bash
# Create and setup a GCE instance for OIDC test.
set -o errexit # Exit on first command error.

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

# Handle secrets from vault.
pushd $DRIVERS_TOOLS/.evergreen/auth_aws
. ./activate-authawsvenv.sh
popd
bash $DRIVERS_TOOLS/.evergreen/secrets_handling/setup-secrets.sh drivers/gcpoidc
source secrets-export.sh

# Set up variables for GCPKMS scripts.
export GCPKMS_SECRETS_FILE=$SCRIPT_DIR/secrets-export.sh
export GCPKMS_SERVICEACCOUNT=$GCPOIDC_SERVICEACCOUNT
export GCPKMS_MACHINE=$GCPOIDC_MACHINE
export GCPKMS_SETUP_INSTANCE="$SCRIPT_DIR/setup-instance.sh"

# Write the keyfile content to a local JSON path.
export GCPKMS_KEYFILE=/tmp/testgcpkms_key_file.json
# convert content from base64 to JSON and write to file
echo ${GCPOIDC_KEYFILE_CONTENT} | base64 --decode > $GCPKMS_KEYFILE

# Create the instance using the script.
bash $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/create-and-setup-instance.sh
