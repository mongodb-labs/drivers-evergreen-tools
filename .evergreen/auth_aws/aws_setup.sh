#!/usr/bin/env bash
#
# aws_setup.sh
#
# Usage:
#   . ./aws_setup.sh <test-name>
#
# Handles AWS credential setup and exports relevant environment variables.

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
pushd $DIR

# Get the secrets from the vault.
. ./setup_secrets.sh drivers/aws_auth
source secrets-export.sh

# Convenience functions.
urlencode () {
  python -c "import sys, urllib.parse as ulp; sys.stdout.write(ulp.quote_plus(sys.argv[1]))" "$1"
}

jsonkey () {
    python -c  "import json,sys;sys.stdout.write(json.load(sys.stdin)[sys.argv[1]])" "$1" < ./creds.json
}

# Handle the auth type.
USER=""
case $1 in
    assume-role)
        python aws_tester.py "$1"
        USER=$(jsonkey AccessKeyId)
        USER=$(urlencode "$USER")
        PASS=$(jsonkey SecretAccessKey)
        PASS=$(urlencode "$PASS")
        SESSION_TOKEN=$(jsonkey SessionToken)
        SESSION_TOKEN=$(urlencode "$SESSION_TOKEN")
        export SESSION_TOKEN
        ;;
    
    session-creds)
        AWS_ACCESS_KEY_ID=$(jsonkey AccessKeyId)
        AWS_SECRET_ACCESS_KEY=$(jsonkey SecretAccessKey)
        AWS_SESSION_TOKEN=$(jsonkey SessionToken)

        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
        export AWS_SESSION_TOKEN
        ;;

    web-identity)
        python aws_tester.py "$1"
        export AWS_ROLE_ARN=$IAM_AUTH_ASSUME_WEB_ROLE_NAME
        export AWS_WEB_IDENTITY_TOKEN_FILE=$IAM_WEB_IDENTITY_TOKEN_FILE
        ;;

    regular)
        python aws_tester.py "$1"
        USER=$(urlencode "${IAM_AUTH_ECS_ACCOUNT}")
        PASS=$(urlencode "${IAM_AUTH_ECS_SECRET_ACCESS_KEY}")
        ;;

    env-creds)
        export AWS_ACCESS_KEY_ID=$IAM_AUTH_ECS_ACCOUNT
        export AWS_SECRET_ACCESS_KEY=$IAM_AUTH_ECS_SECRET_ACCESS_KEY
        ;;

    ecs)
        python aws_tester.py "$1"
        exit 0
        ;;
esac

if [ -n "$USER" ]; then
    MONGODB_URI="mongodb://$USER:$PASS@localhost"
    export USER
    export PASS
fi

MONGODB_URI=${MONGODB_URI:-"mongodb://localhost"}
MONGODB_URI="${MONGODB_URI}/aws?authMechanism=MONGODB-AWS"
if [[ -n ${SESSION_TOKEN} ]]; then
    MONGODB_URI="${MONGODB_URI}&authMechanismProperties=AWS_SESSION_TOKEN:${SESSION_TOKEN}"
fi

export MONGODB_URI="$MONGODB_URI"

popd
