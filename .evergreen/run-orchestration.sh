#!/bin/sh
set -o xtrace   # Write all commands first to stderr
set -o errexit  # Exit the script with error if any of the commands fail


AUTH=${AUTH:-noauth}
SSL=${SSL:-nossl}
TOPOLOGY=${TOPOLOGY:-server}
STORAGE_ENGINE=${STORAGE_ENGINE}
MONGODB_VERSION=${MONGODB_VERSION:-latest}

DL_START=$(date +%s)
DIR=$(dirname $0)
# Functions to fetch MongoDB binaries
. $DIR/download-mongodb.sh

get_distro
if [ -z "$MONGODB_DOWNLOAD_URL" ]; then
    get_mongodb_download_url_for "$DISTRO" "$MONGODB_VERSION"
fi
# Even though we have the MONGODB_DOWNLOAD_URL, we still call this to get the proper EXTRACT variable
get_mongodb_download_url_for "$DISTRO"
download_and_extract "$MONGODB_DOWNLOAD_URL" "$EXTRACT"

DL_END=$(date +%s)
MO_START=$(date +%s)

ORCHESTRATION_FILE="basic"
if [ "$AUTH" = "auth" ]; then
  ORCHESTRATION_FILE="auth"
fi

if [ "$SSL" != "nossl" ]; then
   ORCHESTRATION_FILE="${ORCHESTRATION_FILE}-ssl"
fi

# Storage engine config files do not exist for different topology, auth, or ssl modes.
if [ ! -z "$STORAGE_ENGINE" ]; then
  ORCHESTRATION_FILE="$STORAGE_ENGINE"
fi

export ORCHESTRATION_FILE="$MONGO_ORCHESTRATION_HOME/configs/${TOPOLOGY}s/${ORCHESTRATION_FILE}.json"
export ORCHESTRATION_URL="http://localhost:8889/v1/${TOPOLOGY}s"

echo From shell `date` > $MONGO_ORCHESTRATION_HOME/server.log

cd "$MONGO_ORCHESTRATION_HOME"
# Setup or use the existing virtualenv for mongo-orchestration.
#
# Many of the Linux distros in Evergreen ship Python 2.6 as the
# system Python. Core libraries installed by virtualenv (setuptools,
# pip, wheel) have dropped, or soon will drop, support for Python
# 2.6. Starting with version 14, virtualenv upgrades these libraries
# to the latest available on pypi when creating the virtual environment
# unless you pass --no-download. The --no-download option was also added
# in virtualenv 14. We try with and without --no-download to support
# older versions of virtualenv.
if [ -f venv/bin/activate ]; then
  . venv/bin/activate
elif [ -f venv/Scripts/activate ]; then
  . venv/Scripts/activate
elif virtualenv --system-site-packages --no-download venv || virtualenv --system-site-packages venv  || python -m virtualenv --system-site-packages --no-download venv || python -m virtualenv --system-site-packages venv; then
  if [ -f venv/bin/activate ]; then
    . venv/bin/activate
  elif [ -f venv/Scripts/activate ]; then
    . venv/Scripts/activate
  fi
  # Install from github otherwise mongo-orchestration won't download simplejson
  # with Python 2.6.
  pip install --upgrade 'git+git://github.com/mongodb/mongo-orchestration@master'
  pip freeze
fi
cd -

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

nohup mongo-orchestration $ORCHESTRATION_ARGUMENTS start > $MONGO_ORCHESTRATION_HOME/out.log 2> $MONGO_ORCHESTRATION_HOME/err.log < /dev/null &

ls -la $MONGO_ORCHESTRATION_HOME

sleep 15
curl http://localhost:8889/ --silent --show-errors --max-time 120 --fail

sleep 5

pwd
curl --silent --show-errors --data @"$ORCHESTRATION_FILE" "$ORCHESTRATION_URL" --max-time 600 --fail -o tmp.json
URI=$(python -c 'import sys, json; j=json.load(open("tmp.json")); print(j["mongodb_auth_uri" if "mongodb_auth_uri" in j else "mongodb_uri"])' | tr -d '\r')
echo 'MONGODB_URI: "'$URI'"' > mo-expansion.yml
echo "Cluster URI: $URI"

MO_END=$(date +%s)
MO_ELAPSED=$(expr $MO_END - $MO_START)
DL_ELAPSED=$(expr $DL_END - $DL_START)
cat <<EOT >> $DRIVERS_TOOLS/results.json
{"results": [
  {
    "status": "PASS",
    "test_file": "Orchestration",
    "start": $MO_START,
    "end": $MO_END,
    "elapsed": $MO_ELAPSED
  },
  {
    "status": "PASS",
    "test_file": "Download MongoDB",
    "start": $DL_START,
    "end": $DL_END,
    "elapsed": $DL_ELAPSED
  }
]}

EOT
