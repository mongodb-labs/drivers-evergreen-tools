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

echo From shell `date` > $MONGO_ORCHESTRATION_HOME/server.log

declare det_evergreen_dir
det_evergreen_dir="$(dirname "${BASH_SOURCE[0]}")"
. "$det_evergreen_dir/find-python3.sh"
. "$det_evergreen_dir/venv-utils.sh"

cd "$MONGO_ORCHESTRATION_HOME"

PYTHON="$(find_python3)"

venvcreate "$PYTHON" venv

# Install from github to get the latest mongo-orchestration.
python -m pip install --upgrade 'https://github.com/mongodb/mongo-orchestration/archive/master.tar.gz'
python -m pip list
cd -

# Create default config file if it doesn't exist
if [ ! -f $MONGO_ORCHESTRATION_HOME/orchestration.config ]; then
  MONGODB_BINARIES=${MONGODB_BINARIES:-$(dirname "$(dirname "$0")")/mongodb/bin}
  echo "{ \"releases\": { \"default\": \"$MONGODB_BINARIES\" }}" > $MONGO_ORCHESTRATION_HOME/orchestration.config
fi

ORCHESTRATION_ARGUMENTS="-e default -f $MONGO_ORCHESTRATION_HOME/orchestration.config --socket-timeout-ms=60000 --bind=127.0.0.1 --enable-majority-read-concern"
if [ "Windows_NT" = "$OS" ]; then # Magic variable in cygwin
  ORCHESTRATION_ARGUMENTS="$ORCHESTRATION_ARGUMENTS -s wsgiref"
fi

# Forcibly kill the process listening on port 8889, most likey a wild
# mongo-orchestration left running from a previous task.
if [ "Windows_NT" = "$OS" ]; then # Magic variable in cygwin
  OLD_MO_PID=$(netstat -ano | grep ':8889 .* LISTENING' | awk '{print $5}' | tr -d '[:space:]')
  if [ ! -z "$OLD_MO_PID" ]; then
    taskkill /F /T /PID "$OLD_MO_PID" || true
  fi
else
  OLD_MO_PID=$(lsof -t -i:8889 || true)
  if [ ! -z "$OLD_MO_PID" ]; then
    kill -9 "$OLD_MO_PID" || true
  fi
fi

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
