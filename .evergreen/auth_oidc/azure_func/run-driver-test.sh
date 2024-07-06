#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

# Handle secrets from vault.
source $SCRIPT_DIR/secrets-export.sh

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
    exit 1
fi

func azure functionapp publish $FUNC_APP_NAME
bash $SCRIPT_DIR/invoke.sh
