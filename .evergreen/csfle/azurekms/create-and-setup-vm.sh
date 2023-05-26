#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

if [ -z "${AZUREKMS_VMNAME_PREFIX:-}" ] || \
   [ -z "${AZUREKMS_CLIENTID:-}" ] || \
   [ -z "${AZUREKMS_TENANTID:-}" ] || \
   [ -z "${AZUREKMS_SECRET:-}" ] || \
   [ -z "${AZUREKMS_DRIVERS_TOOLS:-}" ] || \
   [ -z "${AZUREKMS_RESOURCEGROUP:-}" ] || \
   [ -z "${AZUREKMS_PUBLICKEYPATH:-}" ] || \
   [ -z "${AZUREKMS_PRIVATEKEYPATH:-}" ] || \
   [ -z "${AZUREKMS_SCOPE:-}" ]; then
    echo "Please set the following required environment variables"
    echo " AZUREKMS_VMNAME_PREFIX to an identifier string no spaces (e.g. CDRIVER)"
    echo " AZUREKMS_CLIENTID"
    echo " AZUREKMS_TENANTID"
    echo " AZUREKMS_SECRET"
    echo " AZUREKMS_DRIVERS_TOOLS"
    echo " AZUREKMS_PUBLICKEYPATH"
    echo " AZUREKMS_PRIVATEKEYPATH"
    echo " AZUREKMS_SCOPE"
    exit 1
fi

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
"$AZUREKMS_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/login.sh
# Create VM.
. "$AZUREKMS_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/create-vm.sh
export AZUREKMS_VMNAME="$AZUREKMS_VMNAME"
echo "AZUREKMS_VMNAME: $AZUREKMS_VMNAME" > testazurekms-expansions.yml
# Assign role.
"$AZUREKMS_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/assign-role.sh
# Install dependencies.
AZUREKMS_SRC="$AZUREKMS_DRIVERS_TOOLS/.evergreen/csfle/azurekms/remote-scripts/setup-azure-vm.sh" \
AZUREKMS_DST="./" \
    "$AZUREKMS_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREKMS_CMD="./setup-azure-vm.sh" \
    "$AZUREKMS_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh
# Start mongodb.
AZUREKMS_SRC="$AZUREKMS_DRIVERS_TOOLS/.evergreen/csfle/azurekms/remote-scripts/start-mongodb.sh" \
AZUREKMS_DST="./" \
    "$AZUREKMS_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREKMS_CMD="./start-mongodb.sh" \
    "$AZUREKMS_DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh