#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

VARLIST=(
AZUREKMS_CLIENTID
AZUREKMS_SECRET
AZUREKMS_TENANTID
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in "${VARLIST[@]}"; do
  [[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

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
