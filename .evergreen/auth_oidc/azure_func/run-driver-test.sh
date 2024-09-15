#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

# Handle secrets from vault.
source $SCRIPT_DIR/secrets-export.sh

VARLIST=(
FUNC_APP_NAME
FUNC_NAME
FUNC_RUNTIME
MONGODB_URI
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in "${VARLIST[@]}"; do
  [[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

func init --$FUNC_RUNTIME
func azure functionapp publish $FUNC_APP_NAME
bash $SCRIPT_DIR/invoke.sh
