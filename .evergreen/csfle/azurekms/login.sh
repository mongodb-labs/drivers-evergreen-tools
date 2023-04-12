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

echo "Log in to azure ... begin"
az login --service-principal \
    --username "$AZUREKMS_CLIENTID" \
    --password "$AZUREKMS_SECRET" \
    --tenant "$AZUREKMS_TENANTID" \
    >/dev/null
echo "Log in to azure ... end"