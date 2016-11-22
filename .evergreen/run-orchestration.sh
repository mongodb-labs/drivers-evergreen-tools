#!/bin/sh
set -o xtrace   # Write all commands first to stderr
set -o errexit  # Exit the script with error if any of the commands fail

DIR=$(dirname $0)
# Functions to fetch MongoDB binaries
. $DIR/download-mongodb.sh

get_distro
get_mongodb_download_url_for "$DISTRO" "$MONGODB_VERSION"
download_and_extract "$MONGODB_DOWNLOAD_URL" "$EXTRACT"


OS=$(uname -s | tr '[:upper:]' '[:lower:]')

AUTH=${AUTH:-noauth}
SSL=${SSL:-nossl}
TOPOLOGY=${TOPOLOGY:-server}

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


case "$OS" in
   cygwin*)
      # Crazy python stuff to make sure MO is running latest version
      python -m virtualenv venv
      cd venv
      . Scripts/activate
      git clone https://github.com/10gen/mongo-orchestration.git
      cd mongo-orchestration
      pip install .
      cd ../..
      cd $MONGO_ORCHESTRATION_HOME
      nohup mongo-orchestration -f orchestration.config -e default --socket-timeout-ms=60000 --bind=127.0.0.1  --enable-majority-read-concern -s wsgiref start > $MONGO_ORCHESTRATION_HOME/out.log 2> $MONGO_ORCHESTRATION_HOME/err.log < /dev/null &
      ;;
   *)
      nohup mongo-orchestration -f orchestration.config -e default --socket-timeout-ms=60000 --bind=127.0.0.1  --enable-majority-read-concern start > $MONGO_ORCHESTRATION_HOME/out.log 2> $MONGO_ORCHESTRATION_HOME/err.log < /dev/null &
      ;;
esac

sleep 15
curl http://localhost:8889/ --silent --max-time 120 --fail

sleep 5

pwd
curl --silent --data @"$ORCHESTRATION_FILE" "$ORCHESTRATION_URL" --max-time 300 --fail

