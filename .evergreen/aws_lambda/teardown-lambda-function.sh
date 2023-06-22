#!/bin/bash
set -o errexit  # Exit the script with error if any of the commands fail

# Explanation of required environment variables:
#
# LAMBDA_STACK_NAME: The name of the stack on lambda "dbx-<language>-lambda"

# Add git commit to name of function and cluster.
FUNCTION_NAME="${LAMBDA_STACK_NAME}-$(git rev-parse --short HEAD)"

echo "Deleting Lambda Function...\n"
sam delete --stack-name ${FUNCTION_NAME} --no-prompts --region us-east-1
