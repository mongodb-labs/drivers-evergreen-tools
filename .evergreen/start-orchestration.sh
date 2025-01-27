#!/usr/bin/env bash

if [ -z "$BASH" ]; then
  echo "start-orchestration.sh must be run in a Bash shell!" 1>&2
  exit 1
fi

if [ "$#" -ne 1 ]; then
  echo "$0 requires one argument: <MONGO_ORCHESTRATION_HOME>"
  echo "For example: $0 /tmp/mongo-orchestration-home"
  exit 1
fi

set -o errexit  # Exit the script with error if any of the commands fail


MONGO_ORCHESTRATION_HOME="$1"

echo "From shell `date`" > $MONGO_ORCHESTRATION_HOME/server.log

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

declare det_evergreen_dir
det_evergreen_dir=$SCRIPT_DIR
. "$det_evergreen_dir/find-python3.sh"
. "$det_evergreen_dir/venv-utils.sh"

cd "$MONGO_ORCHESTRATION_HOME"

PYTHON=$(ensure_python3)

echo "Creating virtual environment 'venv'..."
venvcreate "${PYTHON:?}" venv
echo "Creating virtual environment 'venv'... done."

# Install from github to get the latest mongo-orchestration, fall back on published wheel.
# The fallback was added to accommodate versions of Python 3 for which there is no compatible version
# of the hatchling backend used by mongo-orchestration.
python -m pip install -q --upgrade 'https://github.com/mongodb/mongo-orchestration/archive/master.tar.gz' || python -m pip install -q --upgrade mongo-orchestration
python -m pip list
cd $DRIVERS_TOOLS

# Create default config file if it doesn't exist
if [ ! -f $MONGO_ORCHESTRATION_HOME/orchestration.config ]; then
  printf '%s' $MONGODB_BINARIES | python -c 'import json,sys; print(json.dumps({"releases": {"default": sys.stdin.read() }}))' > $MONGO_ORCHESTRATION_HOME/orchestration.config
fi

ORCHESTRATION_ARGUMENTS="-e default -f $MONGO_ORCHESTRATION_HOME/orchestration.config --socket-timeout-ms=60000 --bind=127.0.0.1 --enable-majority-read-concern"
if [[ "${OSTYPE:?}" == cygwin ]]; then
  ORCHESTRATION_ARGUMENTS="$ORCHESTRATION_ARGUMENTS -s wsgiref"
fi

# Forcibly kill the process listening on port 8889, most likely a wild
# mongo-orchestration left running from a previous task.
# NOTE: Killing mongo-orchestration with SIGTERM gives it a chance to
# cleanup any running mongo servers.
# Also kill any leftover mongo processes on common ports as a backup.
. "$det_evergreen_dir/process-utils.sh"
for port in 8889 27017 27018 27019 27217 27218 27219 1026; do
  killport $port
done


mongo-orchestration $ORCHESTRATION_ARGUMENTS start > $MONGO_ORCHESTRATION_HOME/out.log 2>&1 < /dev/null &

ls -la $MONGO_ORCHESTRATION_HOME

sleep 5
if ! curl http://localhost:8889/ --silent --show-error --max-time 120 --fail; then
  echo Failed to start mongo-orchestration, see $MONGO_ORCHESTRATION_HOME/out.log:
  cat $MONGO_ORCHESTRATION_HOME/out.log
  echo Failed to start mongo-orchestration, see $MONGO_ORCHESTRATION_HOME/server.log:
  cat $MONGO_ORCHESTRATION_HOME/server.log
  exit 1
fi
sleep 5
