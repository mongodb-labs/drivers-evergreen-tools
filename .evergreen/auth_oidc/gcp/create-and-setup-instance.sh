#!/usr/bin/env bash
# Create and setup a GCE instance for OIDC test.
set -o errexit # Exit on first command error.

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

export GCPKMS_SETUP_INSTANCE=$SCRIPT_DIR/setup-instance.sh

# Handle secrets from vault.
# TODO: after merging the secrets PR, update to use setup-secrets.sh
# also update the list of vaults in secrets-handling/README.
# also update the local README
pushd ../auth_aws
. /activate-authawsvenv.sh
popd
bash ../auth_aws/setup_secrets.sh drivers/gcpoidc
source secrets-export.sh

# TODO: handle keyfile
export GCPKMS_KEYFILE=
cat $GCPOIDC_KEYFILE_CONTENT > 

export GCPKMS_SERVICEACCOUNT=$GCPOIDC_SERVICEACCOUNT
export GCPKMS_MACHINE=$GCPOIDC_MACHINE

bash $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/create-and-setup-instance.sh

# TODO: Write the variable needed for teardown to the secrets file.
# if [ -z "$GCPKMS_GCLOUD" -o -z "$GCPKMS_PROJECT" -o -z "$GCPKMS_ZONE" -o -z "$GCPKMS_INSTANCENAME" ]; then
