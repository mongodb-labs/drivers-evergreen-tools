#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

if [ -z "${AZUREOIDC_VMNAME_PREFIX:-}" ] || \
   [ -z "${AZUREOIDC_CLIENTID:-}" ] || \
   [ -z "${AZUREOIDC_TENANTID:-}" ] || \
   [ -z "${AZUREOIDC_SECRET:-}" ] || \
   [ -z "${AZUREOIDC_DRIVERS_TOOLS:-}" ]; then
    echo "Please set the following required environment variables"
    echo " AZUREOIDC_VMNAME_PREFIX to an identifier string no spaces (e.g. CDRIVER)"
    echo " AZUREOIDC_CLIENTID"
    echo " AZUREOIDC_TENANTID"
    echo " AZUREOIDC_SECRET"
    echo " AZUREOIDC_DRIVERS_TOOLS"
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
export AZUREKMS_IMAGE=${AZUREOIDC_IMAGE:-"Debian:debian-11:11:0.20221020.1174"}

# Check for Azure Command-Line Interface (`az`) version 2.25.0 or newer.
if ! command -v az &> /dev/null; then
    echo "az not detected. See https://github.com/mongodb-labs/drivers-evergreen-tools/blob/master/.evergreen/csfle/azurekms/README.md for supported distros"
    exit 1
fi
EXPECTED_VERSION_NEWER="2.25.0"
ACTUAL_VERSION="$(az version -o tsv | awk '{print $1}')"
if [[ "$(printf "$ACTUAL_VERSION\n$EXPECTED_VERSION_NEWER\n" | sort -rV | head -n 1)" != "$ACTUAL_VERSION" ]]; then
    # az is not new enough.
    echo "Detected az version $ACTUAL_VERSION but need version >= 2.25.0. See https://github.com/mongodb-labs/drivers-evergreen-tools/blob/master/.evergreen/csfle/azurekms/README.md for supported distros"
    exit 1
fi

# Login.
"$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/login.sh
cat $HOME/.azure/msal_token_cache.json

# Handle secrets from vault.
cd $BASE_PATH
. ./activate-authoidcvenv.sh
python ./azure/handle_secrets.py
source $AZUREOIDC_ENVPATH

# Create VM.
. "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/create-vm.sh
export AZUREOIDC_VMNAME="$AZUREKMS_VMNAME"
export AZUREKMS_VMNAME="$AZUREOIDC_VMNAME"

# Update expansions and env viles.
echo "AZUREOIDC_VMNAME: $AZUREOIDC_VMNAME" > testazureoidc-expansions.yml
echo "AZUREOIDC_VMNAME=${AZUREOIDC_VMNAME}" >> $AZUREOIDC_ENVPATH
echo "AZUREOIDC_DRIVERS_TOOLS=${AZUREOIDC_DRIVERS_TOOLS}" >> $AZUREOIDC_ENVPATH

# Install dependencies.
AZUREKMS_SRC="$AZUREOIDC_DRIVERS_TOOLS/.evergreen/csfle/azurekms/remote-scripts/setup-azure-vm.sh" \
AZUREKMS_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREKMS_CMD="./setup-azure-vm.sh" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh

# Write the env variables file
AZUREKMS_SRC=$AZUREOIDC_ENVPATH \
AZUREKMS_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh

# Start mongodb.
AZUREKMS_SRC="$AZUREOIDC_DRIVERS_TOOLS/.evergreen/auth_oidc/azure/start-mongodb.sh" \
AZUREKMS_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREKMS_CMD="./start-mongodb.sh" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh

# Run the self-test
AZUREKMS_SRC="$AZUREOIDC_DRIVERS_TOOLS/.evergreen/auth_oidc/azure/test.py" \
AZUREKMS_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREKMS_SRC="$AZUREOIDC_DRIVERS_TOOLS/.evergreen/auth_oidc/azure/run-test.sh" \
AZUREKMS_DST="./" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREKMS_CMD="./run-test.sh" \
    "$AZUREOIDC_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh
