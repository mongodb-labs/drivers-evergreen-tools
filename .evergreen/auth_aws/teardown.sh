#!/usr/bin/env bash
# Handle proper teardown of Auth AWS.

set -o errexit  # Exit the script with error if any of the commands fail

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

pushd $SCRIPT_DIR
if [ -f "./aws_e2e_setup.json" ] || [ -f "./setup-secrets.sh" ]; then
    . ./activate-authawsvenv.sh
    python ./lib/aws_assign_instance_profile.py
fi
popd
