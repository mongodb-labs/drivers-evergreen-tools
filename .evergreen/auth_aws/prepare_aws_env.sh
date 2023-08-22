#!/usr/bin/env bash
#
# prepare_aws_env.sh
#
# Usage:
#   . ./prepare_aws_env.sh
#
# Loads AWS credentials for an authenticated MongoDB server. Exports the final credentials and server URI as environment variables.
set -x

urlencode () {
  $PYTHON_BINARY -c "import sys, urllib.parse as ulp; sys.stdout.write(ulp.quote_plus(sys.argv[1]))" "$1"
}

if [ -n "$ASSUME_ROLE_CREDENTIALS" ]; then
  jsonkey () {
    $PYTHON_BINARY -c  "import json,sys;sys.stdout.write(json.load(sys.stdin)[sys.argv[1]])" "$1" < "${DRIVERS_TOOLS}"/.evergreen/auth_aws/creds.json
    }

  USER=$(jsonkey AccessKeyId)
  USER=$(urlencode "$USER")
  PASS=$(jsonkey SecretAccessKey)
  PASS=$(urlencode "$PASS")
  SESSION_TOKEN=$(jsonkey SessionToken)
  SESSION_TOKEN=$(urlencode "$SESSION_TOKEN")
  export SESSION_TOKEN
else
  USER=$(urlencode "${IAM_AUTH_ECS_ACCOUNT}")
  PASS=$(urlencode "${IAM_AUTH_ECS_SECRET_ACCESS_KEY}")
fi

MONGODB_URI="mongodb://$USER:$PASS@localhost"

export USER
export PASS
export MONGODB_URI
