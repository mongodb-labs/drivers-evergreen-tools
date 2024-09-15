#!/usr/bin/env bash
# shellcheck shell=sh

set -o errexit  # Exit the script with error if any of the commands fail

# shellcheck disable=SC3028
SCRIPT_DIR=$(dirname "${BASH_SOURCE:-"$0"}")
. "$SCRIPT_DIR/handle-paths.sh"

cd ${DRIVERS_TOOLS}

# source the mongo-orchestration virtualenv if it exists
VENV="$MONGO_ORCHESTRATION_HOME/venv"
if [ -f "$VENV/bin/activate" ]; then
    . "$VENV/bin/activate"
    mongo-orchestration stop
elif [ -f "$VENV/Scripts/activate" ]; then
    . "$VENV/Scripts/activate"
    mongo-orchestration stop
else
    echo "No virtualenv found!"
fi

cd -
