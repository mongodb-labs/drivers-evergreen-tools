#!/bin/bash
set -o errexit  # Exit the script with error if any of the commands fail

# Explanation of required environment variables:
#
# LAMBDA_STACK_NAME: The name of the stack on lambda "dbx-<language>-lambda"

# Explanation of generated variables:
#
# FUNCTION_NAME: Uses the stack name plus the current commit sha to create a unique cluster and function.
# ATLAS_BASE_URL: Where the Atlas API root resides.
# task_id: The `task_id` evergreen expansion associated with the CI run (or a unique identifier with which to create the function name).
#          Note: This MUST be unique per-CI task.  Otherwise, multiple tasks calling this script may attempt to create clusters with the same name.


# The Atlas API version
ATLAS_API_VERSION="v1.0"
# The base Atlas API url. We use the API directly as the CLI does not yet
# support testing cluster outages.
ATLAS_BASE_URL="https://cloud.mongodb.com/api/atlas/$ATLAS_API_VERSION"

# create a unique per CI task tag for the function.
# task_id has the structure $projectID_$variantName_$taskName_$commitHash_$createTime, which is unique per task per ci run per project.
# task_id is NOT unique across restarts of the same task though, so we include execution to ensure that it is unique for every restart too.
# the generated string is hashed to ensure the prefix is unique for every id
TASK_ID=$(echo "${task_id}-${execution}" | base64)

# Add git commit to name of function and cluster.
FUNCTION_NAME="${LAMBDA_STACK_NAME}-${TASK_ID}"