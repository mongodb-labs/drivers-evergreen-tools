#!/bin/bash
set -o errexit  # Exit the script with error if any of the commands fail

# Explanation of required environment variables:
#
# DRIVERS_ATLAS_PUBLIC_API_KEY: The public Atlas key for the drivers org.
# DRIVERS_ATLAS_PRIVATE_API_KEY: The private Atlas key for the drivers org.
# DRIVERS_ATLAS_GROUP_ID: The id of the individual projects under the drivers org, per language.
# LAMBDA_STACK_NAME: The name of the stack on lambda "dbx-<language>-lambda"

# Explanation of generated variables:
#
# FUNCTION_NAME: Uses the stack name plus the current commit sha to create a unique cluster and function.
# ATLAS_BASE_URL: Where the Atlas API root resides.

VARLIST=(
DRIVERS_ATLAS_PUBLIC_API_KEY
DRIVERS_ATLAS_PRIVATE_API_KEY
DRIVERS_ATLAS_GROUP_ID
LAMBDA_STACK_NAME
TASK_ID
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in ${VARLIST[*]}; do
[[ -z "${!VARNAME}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

# Set up the common variables.
DIR="$(dirname "${BASH_SOURCE[0]}")"
. $DIR/setup-variables.sh

# Delete the cluster.
echo "Deleting Atlas Cluster..."
curl \
  --digest -u ${DRIVERS_ATLAS_PUBLIC_API_KEY}:${DRIVERS_ATLAS_PRIVATE_API_KEY} \
  -X DELETE \
  "${ATLAS_BASE_URL}/groups/${DRIVERS_ATLAS_GROUP_ID}/clusters/${FUNCTION_NAME}?pretty=true"
