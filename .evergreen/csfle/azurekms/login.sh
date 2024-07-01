#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

if [ -z "$AZUREKMS_CLIENTID" -o \
     -z "$AZUREKMS_SECRET" -o \
     -z "$AZUREKMS_TENANTID" ]; then
    echo "Please set the following required environment variables"
    echo " AZUREKMS_CLIENTID"
    echo " AZUREKMS_SECRET"
    echo " AZUREKMS_TENANTID"
    exit 1
fi

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

echo "Log in to azure ... begin"
az logout || true
az login --service-principal \
    --username "$AZUREKMS_CLIENTID" \
    --password "$AZUREKMS_SECRET" \
    --tenant "$AZUREKMS_TENANTID" \
    >/dev/null
echo "Log in to azure ... end"
