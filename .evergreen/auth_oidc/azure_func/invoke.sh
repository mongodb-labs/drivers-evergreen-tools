#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

# Handle secrets from vault.
source ./secrets-export.sh

if [ -z "$FUNC_APP_NAME" ]; then
    echo "Missing FUNC_APP_NAME!"
    exit 1
fi

if [ -z "$FUNC_NAME" ]; then
    echo "Missing FUNC_NAME!"
    exit 1
fi

if [ -z "$MONGODB_URI" ]; then
    echo "Missing MONGODB_URI!"
fi

CODE=$(az functionapp function keys list -g $AZUREOIDC_FUNC_RESOURCE_GROUP -n $FUNC_APP_NAME --function-name $FUNC_NAME | jq -r '.default')
URL=https://$FUNC_APP_NAME.azurewebsites.net/api/$FUNC_NAME?code=$CODE
DATA="{\"MONGODB_URI\": \"$MONGODB_URI\" }"

curl -i \
    -X POST \
    -d "$DATA" \
    -H "x-functions-key: $CODE" \
    $URL
