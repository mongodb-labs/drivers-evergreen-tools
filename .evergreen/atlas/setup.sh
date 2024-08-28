#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

. $SCRIPT_DIR/setup-atlas-cluster.sh "$@"

source $SCRIPT_DIR/secrets-export.sh
. ${DRIVERS_TOOLS}/.evergreen/check-connection.sh

# Clean up binary directory.
rm -rf ${DRIVERS_TOOLS}/mongodb
