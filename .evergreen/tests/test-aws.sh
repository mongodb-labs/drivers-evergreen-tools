#!/usr/bin/env bash

# Test aws setup function for different inputs.
set -eu

# Start a server with aws auth enabled.
AUTH="auth"  ORCHESTRATION_FILE="auth-aws.json" make run-server

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/../auth_aws

bash aws_setup.sh assume-role
cat test-env.sh | grep -q USER
cat test-env.sh | grep -q PASS
cat test-env.sh | grep -q SESSION_TOKEN
cat test-env.sh | grep -q MONGODB_URI

bash aws_setup.sh ec2
cat test-env.sh | grep -q MONGODB_URI

bash aws_setup.sh regular
cat test-env.sh | grep -q USER
cat test-env.sh | grep -q PASS
cat test-env.sh | grep -q MONGODB_URI

bash aws_setup.sh session-creds
cat test-env.sh | grep -q AWS_ACCESS_KEY_ID
cat test-env.sh | grep -q AWS_ACCOUNT_ARN
cat test-env.sh | grep -q AWS_SESSION_TOKEN
cat test-env.sh | grep -q MONGODB_URI

bash aws_setup.sh env-creds
cat test-env.sh | grep -q AWS_ACCESS_KEY_ID
cat test-env.sh | grep -q AWS_ACCOUNT_ARN
cat test-env.sh | grep -q MONGODB_URI

bash aws_setup.sh web-identity
cat test-env.sh | grep -q AWS_WEB_IDENTITY_TOKEN_FILE
cat test-env.sh | AWS_ROLE_ARN

bash ./teardown.sh

make stop-server

popd
make -C ${DRIVERS_TOOLS} test
