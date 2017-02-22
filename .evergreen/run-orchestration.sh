#!/bin/sh
set -o xtrace   # Write all commands first to stderr
set -o errexit  # Exit the script with error if any of the commands fail


AUTH=${AUTH:-noauth}
SSL=${SSL:-nossl}
TOPOLOGY=${TOPOLOGY:-server}
STORAGE_ENGINE=${STORAGE_ENGINE}
MONGODB_VERSION=${MONGODB_VERSION:-latest}
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

DL_START=$(date +%s)
DIR=$(dirname $0)
# Functions to fetch MongoDB binaries
. $DIR/download-mongodb.sh

get_distro
get_mongodb_download_url_for "$DISTRO" "$MONGODB_VERSION"
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

if [ ! -z "$STORAGE_ENGINE" ]; then
  ORCHESTRATION_FILE="$STORAGE_ENGINE"
fi

# Only wiredTiger supports enableMajorityReadConcern. This can be removed once
# mongo-orchestration properly checks the storageEngine is compatible.
if [ -z "$STORAGE_ENGINE" || "$STORAGE_ENGINE" = "wiredtiger" ]; then
  ENABLE_MAJORITY_READ_CONCERN="--enable-majority-read-concern"
fi

export ORCHESTRATION_FILE="$MONGO_ORCHESTRATION_HOME/configs/${TOPOLOGY}s/${ORCHESTRATION_FILE}.json"
export ORCHESTRATION_URL="http://localhost:8889/v1/${TOPOLOGY}s"

echo From shell `date` > $MONGO_ORCHESTRATION_HOME/server.log


ORCHESTRATION_ARGUMENTS="-e default -f $MONGO_ORCHESTRATION_HOME/orchestration.config --socket-timeout-ms=60000 --bind=127.0.0.1 $ENABLE_MAJORITY_READ_CONCERN"

cd "$MONGO_ORCHESTRATION_HOME"
# Setup or use the existing virtualenv for mongo-orchestration
if [ -f venv/bin/activate ]; then
  . venv/bin/activate
elif [ -f venv/Scripts/activate ]; then
  . venv/Scripts/activate
elif virtualenv --system-site-packages venv || python -m virtualenv --system-site-packages venv; then
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

case "$OS" in
  cygwin*)
    ORCHESTRATION_ARGUMENTS="$ORCHESTRATION_ARGUMENTS -s wsgiref"
    ;;
esac

nohup mongo-orchestration $ORCHESTRATION_ARGUMENTS start > $MONGO_ORCHESTRATION_HOME/out.log 2> $MONGO_ORCHESTRATION_HOME/err.log < /dev/null &

ls -la $MONGO_ORCHESTRATION_HOME

sleep 15
curl http://localhost:8889/ --silent --max-time 120 --fail

sleep 5

pwd
curl --silent --data @"$ORCHESTRATION_FILE" "$ORCHESTRATION_URL" --max-time 300 --fail > tmp.json
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
