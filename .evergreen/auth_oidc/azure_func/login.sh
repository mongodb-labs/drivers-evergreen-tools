#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

# Handle secrets from vault.
if [ ! -f secrets-export.sh ]; then
    . $DRIVERS_TOOLS/.evergreen/secrets_handling/setup-secrets.sh drivers/azureoidc
fi
source ./secrets-export.sh

export AZUREKMS_TENANTID=$AZUREOIDC_TENANTID
export AZUREKMS_SECRET=$AZUREOIDC_SECRET2
export AZUREKMS_CLIENTID=$AZUREOIDC_APPID
"$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/login.sh

popd
