#!/bin/bash
set -o errexit  # Exit the script with error if any of the commands fail

# Explanation of required environment variables:
#
# DRIVERS_ATLAS_PUBLIC_API_KEY: The public Atlas key for the drivers org.
# DRIVERS_ATLAS_PRIVATE_API_KEY: The private Atlas key for the drivers org.
# DRIVERS_ATLAS_GROUP_ID: The id of the individual projects under the drivers org, per language.
# DRIVERS_ATLAS_LAMBDA_USER: The user for the lambda cluster.
# DRIVERS_ATLAS_LAMBDA_PASSWORD: The password for the user.
# LAMBDA_STACK_NAME: The name of the stack on lambda "dbx-<language>-lambda"
# MONGODB_VERSION: The major version of the cluster to deploy.  Defaults to 6.0.

# Explanation of generated variables:
#
# MONGODB_URI: The URI for the created Atlas cluster during this script.
# FUNCTION_NAME: Uses the stack name plus the current commit sha to create a unique cluster and function.
# CREATE_CLUSTER_JSON: The JSON used to create a cluster via the Atlas API.
# ATLAS_BASE_URL: Where the Atlas API root resides.

VARLIST=(
DRIVERS_ATLAS_PUBLIC_API_KEY
DRIVERS_ATLAS_PRIVATE_API_KEY
DRIVERS_ATLAS_GROUP_ID
DRIVERS_ATLAS_LAMBDA_USER
DRIVERS_ATLAS_LAMBDA_PASSWORD
LAMBDA_STACK_NAME
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in ${VARLIST[*]}; do
[[ -z "${!VARNAME}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

# The Atlas API version
ATLAS_API_VERSION="v1.0"
# The base Atlas API url. We use the API directly as the CLI does not yet
# support testing cluster outages.
ATLAS_BASE_URL="https://cloud.mongodb.com/api/atlas/$ATLAS_API_VERSION"

# Add git commit to name of function and cluster.
FUNCTION_NAME="${LAMBDA_STACK_NAME}-$(git rev-parse --short HEAD)"