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

# Ensure uv is available and source the secrets file.
. $SCRIPT_DIR/../ensure-uv.sh
ensure_uv || exit 1

# Ensure that secrets have already been set up.
if [ ! -f "./secrets-export.sh" ]; then
    bash ./setup-secrets.sh
fi

# Remove any AWS creds that might be set in the parent env.
# We will need those creds for eks to set up the cluster.
if [ $1 != "eks" ]; then
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
fi

source ./secrets-export.sh

if [ -f $SCRIPT_DIR/test-env.sh ]; then
    rm $SCRIPT_DIR/test-env.sh
fi

export PROJECT_DIRECTORY
# The auth_aws group is defined in the root pyproject.toml, so run from the
# root project context. DRIVERS_TOOLS is set absolutely by handle-paths.sh.
uv run --project "$DRIVERS_TOOLS" --group auth_aws python aws_tester.py "$@"

# Remove any AWS creds that might be set in the parent env.
if [ $1 == "eks" ]; then
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
fi

source $SCRIPT_DIR/test-env.sh

popd
