#!/bin/sh
set -o xtrace   # Write all commands first to stderr
set -o errexit  # Exit the script with error if any of the commands fail


AUTH=${AUTH:-noauth}
SSL=${SSL:-nossl}
TOPOLOGY=${TOPOLOGY:-server}
MONGODB_VERSION=${MONGODB_VERSION:-latest}
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

EVG=${EVG:-`pwd`} # The evergreen working directory

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

export ORCHESTRATION_FILE="$MONGO_ORCHESTRATION_HOME/configs/${TOPOLOGY}s/${ORCHESTRATION_FILE}.json"
export ORCHESTRATION_URL="http://localhost:8889/v1/${TOPOLOGY}s"

echo From shell `date` > $MONGO_ORCHESTRATION_HOME/server.log


ORCHESTRATION_ARGUMENTS="-e default -f $MONGO_ORCHESTRATION_HOME/orchestration.config --socket-timeout-ms=60000 --bind=127.0.0.1 --enable-majority-read-concern"
case "$OS" in
   cygwin*)
      # Crazy python stuff to make sure MO is running latest version
      python -m virtualenv venv
      cd venv
      . Scripts/activate
      git clone https://github.com/10gen/mongo-orchestration.git
      cd mongo-orchestration
      pip install .
      nohup mongo-orchestration $ORCHESTRATION_ARGUMENTS -s wsgiref start > $MONGO_ORCHESTRATION_HOME/out.log 2> $MONGO_ORCHESTRATION_HOME/err.log < /dev/null &
      cd ../..
      ;;
   *)
      nohup mongo-orchestration $ORCHESTRATION_ARGUMENTS start > $MONGO_ORCHESTRATION_HOME/out.log 2> $MONGO_ORCHESTRATION_HOME/err.log < /dev/null &
      ;;
esac

ls -la $MONGO_ORCHESTRATION_HOME

sleep 15
curl http://localhost:8889/ --silent --max-time 120 --fail

sleep 5

pwd
curl --silent --data @"$ORCHESTRATION_FILE" "$ORCHESTRATION_URL" --max-time 300 --fail > $EVG/description.json
URI=$(python -c 'import sys, json; j=json.load(open("'$EVG'/description.json")); print j["mongodb_auth_uri" if "mongodb_auth_uri" in j else "mongodb_uri"]')
echo 'MONGODB_URI: "$URI"' > $EVG/mo-expansion.yml
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
