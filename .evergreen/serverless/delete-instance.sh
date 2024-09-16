#!/usr/bin/env bash

set -o errexit
set +o xtrace # Disable xtrace to ensure credentials aren't leaked

# Supported environment variables:
#
#   SERVERLESS_INSTANCE_NAME    Required. Serverless instance to delete.
#   SERVERLESS_DRIVERS_GROUP    Required. Atlas group for drivers testing.
#   SERVERLESS_API_PUBLIC_KEY   Required. Public key for Atlas API request.
#   SERVERLESS_API_PRIVATE_KEY  Required. Private key for Atlas API request.

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

# Ensure that secrets have already been set up.
if [ -f "$SCRIPT_DIR/secrets-export.sh" ]; then
  source "$SCRIPT_DIR/secrets-export.sh"
fi

VARLIST=(
SERVERLESS_INSTANCE_NAME
SERVERLESS_DRIVERS_GROUP
SERVERLESS_API_PRIVATE_KEY
SERVERLESS_API_PUBLIC_KEY
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in "${VARLIST[@]}"; do
  [[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

echo "Deleting serverless instance \"$SERVERLESS_INSTANCE_NAME\"..."

# See: https://www.mongodb.com/docs/atlas/reference/api/serverless/remove-one-serverless-instance/
API_BASE_URL="https://account-dev.mongodb.com/api/atlas/v1.0/groups/$SERVERLESS_DRIVERS_GROUP"

curl \
  --silent \
  --show-error \
  -u "$SERVERLESS_API_PUBLIC_KEY:$SERVERLESS_API_PRIVATE_KEY" \
  -X DELETE \
  --digest \
  --header "Accept: application/json" \
  --header "Content-Type: application/json" \
  "${API_BASE_URL}/serverless/${SERVERLESS_INSTANCE_NAME}?pretty=true"

echo ""
echo "Deleting serverless instance \"$SERVERLESS_INSTANCE_NAME\"... done."
