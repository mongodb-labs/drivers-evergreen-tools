#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

. $SCRIPT_DIR/setup-atlas-cluster.sh "$@"

bash ${DRIVERS_TOOLS}/.evergreen/check-connection.sh
