#!/bin/bash
set -o errexit  # Exit the script with error if any of the commands fail

# Explanation of required environment variables:
#
# TEST_LAMBDA_DIRECTORY: The root of the project's Lambda sam project.
# DRIVERS_ATLAS_PUBLIC_API_KEY: The public Atlas key for the drivers org.
# DRIVERS_ATLAS_PRIVATE_API_KEY: The private Atlas key for the drivers org.
# DRIVERS_ATLAS_GROUP_ID: The id of the individual projects under the drivers org, per language.
# LAMBDA_STACK_NAME: The name of the stack on lambda "dbx-<language>-lambda"
# AWS_REGION: The region for the function - generally us-east-1

# Explanation of generated variables:
#
# FUNCTION_NAME: Uses the stack name plus the current commit sha to create a unique cluster and function.
# CREATE_CLUSTER_JSON: The JSON used to create a cluster via the Atlas API.
# ATLAS_BASE_URL: Where the Atlas API root resides.

# The base Atlas API url. We use the API directly as the CLI does not yet
# support testing cluster outages.
ATLAS_BASE_URL="https://cloud.mongodb.com/api/atlas/v1.0"

# Add git commit to name of function and cluster.
FUNCTION_NAME="${LAMBDA_STACK_NAME}-$(git rev-parse --short HEAD)"

# Restarts the cluster's primary node.
restart_cluster_primary ()
{
  echo "Testing Atlas primary restart..."
  curl \
    --digest -u ${DRIVERS_ATLAS_PUBLIC_API_KEY}:${DRIVERS_ATLAS_PRIVATE_API_KEY} \
    -X POST \
    "${ATLAS_BASE_URL}/groups/${DRIVERS_ATLAS_GROUP_ID}/clusters/${FUNCTION_NAME}/restartPrimaries"
}

# Deploys a lambda function to the set stack name.
deploy_lambda_function ()
{
  echo "Deploying Lambda function..."
  sam deploy \
    --stack-name "${FUNCTION_NAME}" \
    --capabilities CAPABILITY_IAM \
    --resolve-s3 \
    --parameter-overrides "MongoDbUri=${MONGODB_URI}" \
    --region ${AWS_REGION}
}

# Get the ARN for the Lambda function we created and export it.
get_lambda_function_arn ()
{
  echo "Getting Lambda function ARN..."
  LAMBDA_FUNCTION_ARN=$(sam list stack-outputs \
    --stack-name ${FUNCTION_NAME} \
    --region ${AWS_REGION} \
    --output json | jq '.[] | select(.OutputKey == "MongoDBFunction") | .OutputValue' | tr -d '"'
  )
  echo "Lambda function ARN: $LAMBDA_FUNCTION_ARN"
  export LAMBDA_FUNCTION_ARN=$LAMBDA_FUNCTION_ARN
}

# Delete the lambda cloud formation stack.
delete_lambda_stack ()
{
  echo "Deleting Lambda Stack..."
  sam delete --stack-name ${FUNCTION_NAME} --no-prompts --region us-east-1
}

cd "${TEST_LAMBDA_DIRECTORY}"

sam build

deploy_lambda_function

get_lambda_function_arn

aws lambda invoke --function-name ${LAMBDA_FUNCTION_ARN} --log-type Tail lambda-invoke-standard.json
tail lambda-invoke-standard.json

echo "Sleeping 1 minute to build up some streaming protocol heartbeats..."
sleep 60
aws lambda invoke --function-name ${LAMBDA_FUNCTION_ARN} --log-type Tail lambda-invoke-frozen.json
tail lambda-invoke-frozen.json

restart_cluster_primary

echo "Sleeping 1 minute to build up some streaming protocol heartbeats..."
sleep 60
aws lambda invoke --function-name ${LAMBDA_FUNCTION_ARN} --log-type Tail lambda-invoke-outage.json
tail lambda-invoke-outage.json

delete_lambda_stack || true
