#!/usr/bin/env bash
#
# aws_setup.sh
#
# Usage:
#   . ./aws_setup.sh <test-name>
#
# Handles AWS credential setup and exports relevant environment variables.
# Sets up secrets if they have not already been set up.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Activate the venv and source the secrets file.
. ./activate-authawsvenv.sh

# Ensure that secrets have already been set up.
if [ ! -f "./secrets-export.sh" ]; then
    bash ./setup-secrets.sh
fi

# Remove any AWS creds that might be set in the parent env.
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

source ./secrets-export.sh

if [ -f $SCRIPT_DIR/test-env.sh ]; then
    rm $SCRIPT_DIR/test-env.sh
fi

python aws_tester.py "$1"
source $SCRIPT_DIR/test-env.sh

popd
