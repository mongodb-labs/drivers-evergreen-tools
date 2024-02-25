#!/usr/bin/env bash
# Handle proper teardown of Azure KMS.

set -o errexit  # Exit the script with error if any of the commands fail

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

if [ -f "$SCRIPT_DIR/secrets-export.sh" ]; then
    $SCRIPT_DIR/stop-servers.sh
    rm $SCRIPT_DIR/pykmip.db
fi
