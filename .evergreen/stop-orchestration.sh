#!/usr/bin/env bash
set -o errexit  # Exit the script with error if any of the commands fail

SCRIPT_DIR=$(dirname ${BASH_SOURCE:-$0})
. $SCRIPT_DIR/handle-paths.sh

pushd "$MONGO_ORCHESTRATION_HOME" > /dev/null
# source the mongo-orchestration virtualenv if it exists
if [ -f venv/bin/activate ]; then
    . venv/bin/activate
elif [ -f venv/Scripts/activate ]; then
    . venv/Scripts/activate
else
    echo "No virtualenv found!"
    exit 1
fi
popd > /dev/null

pushd ${DRIVERS_TOOLS} > /dev/null
mongo-orchestration stop
popd > /dev/null
