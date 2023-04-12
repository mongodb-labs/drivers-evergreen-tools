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

# TODO: Get resource group, public key path, private key path from vault

# Translate env variables for KMS scripts.
export AZUREKMS_CLIENTID=$AZUREOIDC_CLIENTID
export AZUREKMS_VMNAME_PREFIX=$AZUREOIDC_VMNAME_PREFIX
export AZUREKMS_TENANTID=$AZUREOIDC_TENANTID
export AZUREKMS_SECRET=$AZUREOIDC_SECRET
export AZUREKMS_RESOURCEGROUP=$AZUREOIDC_RESOURCEGROUP
export AZUREKMS_PUBLICKEYPATH=$AZUREOIDC_PUBLICKEYPATH
export AZUREKMS_PRIVATEKEYPATH=$AZUREOIDC_PRIVATEKEYPATH

# Set defaults.
export AZUREOKMS_IMAGE=${AZUREOIDC_IMAGE:-"Debian:debian-11:11:0.20221020.1174"}
# Install az.
#"$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/install-az.sh
# Login.
"$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/login.sh
# Create VM.
. "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/create-vm.sh
export AZUREOIDC_VMNAME="$AZUREOIDC_VMNAME"
echo "AZUREOIDC_VMNAME: $AZUREOIDC_VMNAME" > testazurekms-expansions.yml
# Assign role.
"$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/assign-role.sh
# Install dependencies.
AZUREOIDC_SRC="$AZUREOIDC_DRIVERS_TOOLS/.evergreen/csfle/azurekms/remote-scripts/setup-azure-vm.sh" \
AZUREOIDC_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREOIDC_CMD="./setup-azure-vm.sh" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh

# Write the env variables file
# TODO: these will be in the vault
AZUREOIDC_SRC="$AZUREOIDC_DRIVERS_TOOLS/.evergreen/auth_oidc/azure/env.sh"
cat <<EOF > $AZUREOIDC_SRC
   export AZUREOIDC_CLIENTID=${AZUREOIDC_CLIENTID}
   export AZUREOIDC_TENANTID=${AZUREOIDC_TENANTID}
   export AZUREOIDC_APPID=${AZUREOIDC_APPID}
   export AZUREOIDC_TOKENCLIENT=${AZUREOIDC_TOKENCLIENT}
   export OIDC_AUTH_PREFIX=OIDC_test
   export OIDC_AUTH_CLAIM=${AZUREOIDC_AUTH_CLAIM}
EOF
AZUREOIDC_SRC="$AZUREOIDC_SRC" \
AZUREOIDC_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh

# Start mongodb.
AZUREOIDC_SRC="$AZUREOIDC_DRIVERS_TOOLS/.evergreen/auth_oidc/azure/start-mongodb.sh" \
AZUREOIDC_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREOIDC_CMD="./start-mongodb.sh" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh
# Run the test
AZUREOIDC_SRC="$AZUREOIDC_DRIVERS_TOOLS/.evergreen/auth_oidc/azure/test.py" \
AZUREOIDC_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREOIDC_SRC="$AZUREOIDC_DRIVERS_TOOLS/.evergreen/auth_oidc/azure/run-test.sh" \
AZUREOIDC_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREOIDC_CMD="./run-test.sh" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh