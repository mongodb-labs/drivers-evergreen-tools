#!/usr/bin/env bash
# Handle setup for orchestration

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

# Install CLIs into this directory (default path for $PROJECT_ORCHESTRATION_HOME
# and $MONGO_ORCHESTRATION_HOME) and the parent directory ($DRIVERS_TOOLS).
bash $SCRIPT_DIR/../install-cli.sh $SCRIPT_DIR/..
bash $SCRIPT_DIR/../install-cli.sh $SCRIPT_DIR
