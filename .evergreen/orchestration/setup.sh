#!/usr/bin/env bash
# Handle setup for orchestration

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

# Install the clis in this folder.
bash $SCRIPT_DIR/../install-cli.sh $SCRIPT_DIR
