#!/usr/bin/env bash
set -o errexit  # Exit the script with error if any of the commands fail

cd "$MONGO_ORCHESTRATION_HOME"
# source the mongo-orchestration virtualenv if it exists
if [ -f venv/bin/activate ]; then
    . venv/bin/activate
    mongo-orchestration stop
elif [ -f venv/Scripts/activate ]; then
    . venv/Scripts/activate
    mongo-orchestration stop
else
    echo "No mongo orchestration to stop!"
fi
