#!/bin/bash
set -o errexit  # Exit the script with error if any of the commands fail

# Explanation of required environment variables:
#
# LAMBDA_STACK_NAME: The name of the stack on lambda "dbx-<language>-lambda"

# Explanation of generated variables:
#
# FUNCTION_NAME: Uses the stack name plus the current commit sha to create a unique cluster and function.
# ATLAS_BASE_URL: Where the Atlas API root resides.


# The Atlas API version
ATLAS_API_VERSION="v1.0"
# The base Atlas API url. We use the API directly as the CLI does not yet
# support testing cluster outages.
ATLAS_BASE_URL="https://cloud.mongodb.com/api/atlas/$ATLAS_API_VERSION"

# Add git commit to name of function and cluster.
FUNCTION_NAME="${LAMBDA_STACK_NAME}-$(git rev-parse --short HEAD)"