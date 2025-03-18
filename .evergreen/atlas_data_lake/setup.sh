#!/usr/bin/env bash
#
# This script sets Atlas Data Lake tests.
#
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

bash $SCRIPT_DIR/pull-mongohouse-image.sh
bash $SCRIPT_DIR/run-mongohouse-image.sh
