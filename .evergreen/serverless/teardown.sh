#!/usr/bin/env bash
# Handle proper teardown of serverless.

set -o errexit  # Exit the script with error if any of the commands fail

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

if [ -f "$SCRIPT_DIR/setup-secrets.sh" ]; then
    $SCRIPT_DIR/delete-instance.sh
fi
