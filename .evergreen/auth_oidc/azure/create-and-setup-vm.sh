#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# Ensure required variables are set.
if [ -z "${AZUREOIDC_VMNAME_PREFIX:-}" ]; then
    echo "Please set the following required environment variables"
    echo " AZUREOIDC_VMNAME_PREFIX to an identifier string no spaces (e.g. CDRIVER)"
    exit 1
fi

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

# Set defaults.
export AZUREKMS_PUBLICKEYPATH="$SCRIPT_DIR/keyfile.pub"
export AZUREKMS_PRIVATEKEYPATH="$SCRIPT_DIR/keyfile"
export AZUREKMS_CERTFILE="$SCRIPT_DIR/cert.pem"
export AZUREKMS_VMNAME_PREFIX=$AZUREOIDC_VMNAME_PREFIX
export AZUREOIDC_ENVPATH="$SCRIPT_DIR/env.sh"
export AZUREKMS_IMAGE=${AZUREOIDC_IMAGE:-"Debian:debian-11:11:0.20221020.1174"}

# Handle secrets from AWS vault.
if [ ! -f ./secrets-export.sh ]; then
    . ./setup-secrets.sh
fi
source ./secrets-export.sh

echo "${AZUREOIDC_CERT}" | base64 --decode > $AZUREKMS_CERTFILE
# Set 600 permissions on cert file. Otherwise ssh / scp may error with permissions "are too open".
chmod 600 $AZUREKMS_CERTFILE

export AZUREKMS_TENANTID=$AZUREOIDC_TENANTID
export AZUREKMS_SECRET=$AZUREOIDC_SECRET
export AZUREKMS_CLIENTID=$AZUREOIDC_APPID

# Login.
. "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/login.sh

# Get the rest of the secrets from the Azure vault.
pushd ..
. ./activate-authoidcvenv.sh
popd
python ./handle_secrets.py
# shellcheck source=env.sh
source $AZUREOIDC_ENVPATH

# Create VM.
. "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/create-vm.sh
export AZUREOIDC_VMNAME="$AZUREKMS_VMNAME"
export AZUREKMS_VMNAME="$AZUREOIDC_VMNAME"

# Update secrets file for teardown.
echo "export AZUREOIDC_VMNAME=${AZUREOIDC_VMNAME}" >> $AZUREOIDC_ENVPATH

# Install dependencies.
AZUREKMS_SRC="$DRIVERS_TOOLS/.evergreen/csfle/azurekms/remote-scripts/setup-azure-vm.sh" \
AZUREKMS_DST="./" \
    "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREKMS_CMD="./setup-azure-vm.sh" \
    "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh

# Write the env variables file
AZUREKMS_SRC=$AZUREOIDC_ENVPATH \
AZUREKMS_DST="./" \
    "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh

# Push Drivers Evergreen Tools onto the VM
TARFILE=/tmp/drivers-evergreen-tools.tgz
pushd $DRIVERS_TOOLS
git archive --format=tar.gz -o $TARFILE --prefix=drivers-evergreen-tools/ HEAD
TARFILE_BASE=$(basename ${TARFILE})
AZUREKMS_SRC=${TARFILE} \
    AZUREKMS_DST="./" \
    $DRIVERS_TOOLS/.evergreen/csfle/azurekms/copy-file.sh
echo "Copying files ... end"
echo "Untarring file ... begin"
AZUREKMS_CMD="tar xf ${TARFILE_BASE}" \
  $DRIVERS_TOOLS/.evergreen/csfle/azurekms/run-command.sh
echo "Untarring file ... end"
popd

# Start mongodb.
AZUREKMS_CMD="./drivers-evergreen-tools/.evergreen/auth_oidc/azure/remote-scripts/start-mongodb.sh" \
    "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh

# Run the self-test
AZUREKMS_CMD="./drivers-evergreen-tools/.evergreen/auth_oidc/azure/remote-scripts/run-self-test.sh" \
    "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh

popd
