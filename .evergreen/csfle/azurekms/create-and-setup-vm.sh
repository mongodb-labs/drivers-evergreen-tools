#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -n "${AZUREKMS_PUBLICKEY:-}" ]; then
    echo "${AZUREKMS_PUBLICKEY}" > /tmp/testazurekms_publickey
    printf -- "${AZUREKMS_PRIVATEKEY}" > /tmp/testazurekms_privatekey
    # Set 600 permissions on private key file. Otherwise ssh / scp may error with permissions "are too open".
    chmod 600 /tmp/testazurekms_privatekey
    export AZUREKMS_PUBLICKEYPATH="/tmp/testazurekms_publickey"
    export AZUREKMS_PRIVATEKEYPATH="/tmp/testazurekms_privatekey"
fi

VARLIST=(
AZUREKMS_VMNAME_PREFIX
AZUREKMS_CLIENTID
AZUREKMS_TENANTID
AZUREKMS_SECRET
AZUREKMS_RESOURCEGROUP
AZUREKMS_PUBLICKEYPATH
AZUREKMS_PRIVATEKEYPATH
AZUREKMS_SCOPE
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in ${VARLIST[*]}; do
[[ -z "${!VARNAME}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

# Set defaults.
export AZUREKMS_IMAGE=${AZUREKMS_IMAGE:-"Debian:debian-11:11:0.20221020.1174"}

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
"$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/login.sh
# Create VM.
. "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/create-vm.sh
export AZUREKMS_VMNAME="$AZUREKMS_VMNAME"
# Store items needed for teardown.
cat <<EOT > testazurekms-expansions.yml
AZUREKMS_VMNAME: $AZUREKMS_VMNAME
AZUREKMS_RESOURCEGROUP: $AZUREKMS_RESOURCEGROUP
AZUREKMS_SCOPE: $AZUREKMS_SCOPE
EOT
# Assign role.
"$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/assign-role.sh
# Install dependencies.
AZUREKMS_SRC="$DRIVERS_TOOLS/.evergreen/csfle/azurekms/remote-scripts/setup-azure-vm.sh" \
AZUREKMS_DST="./" \
    "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREKMS_CMD="./setup-azure-vm.sh" \
    "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh
# Start mongodb.
AZUREKMS_SRC="$DRIVERS_TOOLS/.evergreen/csfle/azurekms/remote-scripts/start-mongodb.sh" \
AZUREKMS_DST="./" \
    "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREKMS_CMD="./start-mongodb.sh" \
    "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh
