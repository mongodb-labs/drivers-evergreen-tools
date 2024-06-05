#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

. $SCRIPT_DIR/create-instance.sh

source ${SCRIPT_DIR}/secrets-export.sh
export MONGODB_URI=$SERVERLESS_URI
. ${DRIVERS_TOOLS}/.evergreen/check-connection.sh
