#!/usr/bin/env bash
#
# aws_setup.sh
#
# Usage:
#   . ./aws_setup.sh <test-name>
#
# Handles AWS credential setup and exports relevant environment variables.
# Assumes you have already set up secrets.
set -eux

DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
. $DIR/../handle-paths.sh
pushd $DIR

# Ensure that secrets have already been set up.
if [ ! -f "secrets-export.sh" ]; then 
    echo "ERROR: please run './setup_secrets.sh drivers/aws_auth' in this folder"
fi

# Activate the venv and source the secrets file.
. ./activate-authawsvenv.sh
source secrets-export.sh

if [ "$1" == "web-identity" ]; then
    export AWS_WEB_IDENTITY_TOKEN_FILE="./token_file.txt"
fi

# Handle the test setup if not using env variables.
case $1 in
    session-creds | env-creds)
        echo "Skipping aws_tester.py"
        ;;
    *)
        python aws_tester.py "$1"
        ;;
esac

# If this is ecs, exit now.
if [ "$1" == "ecs" ]; then
    exit 0
fi

# Convenience functions.
urlencode () {
  python -c "import sys, urllib.parse as ulp; sys.stdout.write(ulp.quote_plus(sys.argv[1]))" "$1"
}

jsonkey () {
    python -c  "import json,sys;sys.stdout.write(json.load(sys.stdin)[sys.argv[1]])" "$1" < ./creds.json
}

# Handle extra vars based on auth type.
USER=""
case $1 in
    assume-role)
        USER=$(jsonkey AccessKeyId)
        USER=$(urlencode "$USER")
        PASS=$(jsonkey SecretAccessKey)
        PASS=$(urlencode "$PASS")
        SESSION_TOKEN=$(jsonkey SessionToken)
        SESSION_TOKEN=$(urlencode "$SESSION_TOKEN")
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
        export AWS_ROLE_ARN=$IAM_AUTH_ASSUME_WEB_ROLE_NAME
        export AWS_WEB_IDENTITY_TOKEN_FILE="$SCRIPT_DIR/$AWS_WEB_IDENTITY_TOKEN_FILE"
        ;;

    regular)
        USER=$(urlencode "${IAM_AUTH_ECS_ACCOUNT}")
        PASS=$(urlencode "${IAM_AUTH_ECS_SECRET_ACCESS_KEY}")
        ;;

    env-creds)
        export AWS_ACCESS_KEY_ID=$IAM_AUTH_ECS_ACCOUNT
        export AWS_SECRET_ACCESS_KEY=$IAM_AUTH_ECS_SECRET_ACCESS_KEY
        ;;
esac

# Handle the URI.
if [ -n "$USER" ]; then
    MONGODB_URI="mongodb://$USER:$PASS@localhost"
    export USER
    export PASS
else
    MONGODB_URI="mongodb://localhost"
fi
MONGODB_URI="${MONGODB_URI}/aws?authMechanism=MONGODB-AWS"
if [[ -n ${SESSION_TOKEN:-} ]]; then
    MONGODB_URI="${MONGODB_URI}&authMechanismProperties=AWS_SESSION_TOKEN:${SESSION_TOKEN}"
fi

export MONGODB_URI="$MONGODB_URI"

popd
