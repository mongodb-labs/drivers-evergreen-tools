#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

if [ -z "${AZUREOIDC_VMNAME_PREFIX:-}" ] || \
   [ -z "${AZUREOIDC_CLIENTID:-}" ] || \
   [ -z "${AZUREOIDC_TENANTID:-}" ] || \
   [ -z "${AZUREOIDC_SECRET:-}" ] || \
   [ -z "${AZUREOIDC_DRIVERS_TOOLS:-}" ] || \
   [ -z "${AZUREOIDC_KEYVAULT:-}" ]; then
    echo "Please set the following required environment variables"
    echo " AZUREOIDC_VMNAME_PREFIX to an identifier string no spaces (e.g. CDRIVER)"
    echo " AZUREOIDC_CLIENTID"
    echo " AZUREOIDC_TENANTID"
    echo " AZUREOIDC_SECRET"
    echo " AZUREOIDC_DRIVERS_TOOLS"
    echo " AZUREOIDC_KEYVAULT"
    exit 1
fi

# Set defaults.
BASE_PATH="$AZUREOIDC_DRIVERS_TOOLS/.evergreen/auth_oidc"
export AZUREKMS_PUBLICKEYPATH="$BASE_PATH/azure/keyfile.pub"
export AZUREKMS_PRIVATEKEYPATH="$BASE_PATH/azure/keyfile"
export AZUREKMS_CLIENTID=$AZUREOIDC_CLIENTID
export AZUREKMS_VMNAME_PREFIX=$AZUREOIDC_VMNAME_PREFIX
export AZUREKMS_TENANTID=$AZUREOIDC_TENANTID
export AZUREKMS_SECRET=$AZUREOIDC_SECRET
export AZUREOIDC_ENVPATH="$BASE_PATH/azure/env.sh"
export AZUREOKMS_IMAGE=${AZUREOIDC_IMAGE:-"Debian:debian-11:11:0.20221020.1174"}

# Install az.
"$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/install-az.sh

# Login.
"$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/login.sh

# Handle secrets from vault.
. ./activate-authoidcvenv.sh
python $BASE_PATH/azure/handle_secrets.py
source $AZUREOIDC_ENVPATH

exit 0

# Create VM.
. "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/create-vm.sh
export AZUREOIDC_VMNAME="$AZUREOIDC_VMNAME"
echo "AZUREOIDC_VMNAME: $AZUREOIDC_VMNAME" > testazureoidc-expansions.yml

# Assign role.
"$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/assign-role.sh

# Install dependencies.
AZUREOIDC_SRC="$AZUREOIDC_DRIVERS_TOOLS/.evergreen/csfle/azurekms/remote-scripts/setup-azure-vm.sh" \
AZUREOIDC_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREOIDC_CMD="./setup-azure-vm.sh" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh

# Write the env variables file
AZUREOIDC_SRC=$AZUREOIDC_ENVPATH \
AZUREOIDC_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh

# Start mongodb.
AZUREOIDC_SRC="$AZUREOIDC_DRIVERS_TOOLS/.evergreen/auth_oidc/azure/start-mongodb.sh" \
AZUREOIDC_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREOIDC_CMD="./start-mongodb.sh" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh

# Run the self-test
AZUREOIDC_SRC="$AZUREOIDC_DRIVERS_TOOLS/.evergreen/auth_oidc/azure/test.py" \
AZUREOIDC_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREOIDC_SRC="$AZUREOIDC_DRIVERS_TOOLS/.evergreen/auth_oidc/azure/run-test.sh" \
AZUREOIDC_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREOIDC_CMD="./run-test.sh" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh