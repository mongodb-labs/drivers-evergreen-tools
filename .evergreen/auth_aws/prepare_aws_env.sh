#!/usr/bin/env bash
#
# prepare_aws_env.sh
#
# Usage:
#   . ./prepare_aws_env.sh
#
# Loads AWS credentials for an authenticated MongoDB server. Exports the final credentials and server URI as environment variables.

alias urlencode='${python3_binary} -c "import sys, urllib.parse as ulp; sys.stdout.write(ulp.quote_plus(sys.argv[1]))"'
alias jsonkey='${python3_binary} -c "import json,sys;sys.stdout.write(json.load(sys.stdin)[sys.argv[1]])" < ${DRIVERS_TOOLS}/.evergreen/auth_aws/creds.json'
USER=$(jsonkey AccessKeyId)
USER=$(urlencode "$USER")
PASS=$(jsonkey SecretAccessKey)
PASS=$(urlencode "$PASS")
SESSION_TOKEN=$(jsonkey SessionToken)
SESSION_TOKEN=$(urlencode "$SESSION_TOKEN")
MONGODB_URI="mongodb://$USER:$PASS@localhost"

export USER
export PASS
export SESSION_TOKEN
export MONGODB_URI
