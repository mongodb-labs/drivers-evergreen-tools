#!/usr/bin/env bash
set -o errexit  # Exit the script with error if any of the commands fail

SCRIPT_DIR=$(dirname "${BASH_SOURCE:-"$0"}")
. $SCRIPT_DIR/handle-paths.sh

cd ${DRIVERS_TOOLS}

# source the mongo-orchestration virtualenv if it exists
if [ -f venv/bin/activate ]; then
    . $MONGO_ORCHESTRATION_HOME/venv/bin/activate
    mongo-orchestration stop
elif [ -f venv/Scripts/activate ]; then
    . $MONGO_ORCHESTRATION_HOME/venv/Scripts/activate
    mongo-orchestration stop
else
    echo "No virtualenv found!"
fi

cd -
