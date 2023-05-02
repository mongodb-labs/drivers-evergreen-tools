#!/bin/sh
set -o errexit  # Exit the script with error if any of the commands fail

# Supported environment variables:
#   AUTH                   Set to "auth" to enable authentication. Defaults to "noauth"
#   SSL                    Set to "yes" to enable SSL. Defaults to "nossl"
#   TOPOLOGY               Set to "server", "replica_set", or "sharded_cluster". Defaults to "server" (i.e. standalone).
#   LOAD_BALANCER          Set to a non-empty string to enable load balancer. Only supported for sharded clusters.
#   STORAGE_ENGINE         Set to a non-empty string to use the <topology>/<storage_engine>.json configuration (e.g. STORAGE_ENGINE=inmemory).
#   REQUIRE_API_VERSION    Set to a non-empty string to set the requireApiVersion parameter. Currently only supported for standalone servers.
#   DISABLE_TEST_COMMANDS  Set to a non-empty string to use the <topology>/disableTestCommands.json configuration (e.g. DISABLE_TEST_COMMANDS=1).
#   MONGODB_VERSION        Set to a MongoDB version to use for download-mongodb.sh. Defaults to "latest".
#   MONGODB_DOWNLOAD_URL   Set to a MongoDB download URL to use for download-mongodb.sh.
#   ORCHESTRATION_FILE     Set to a non-empty string to use the <topology>/<orchestration_file>.json configuration.

AUTH=${AUTH:-noauth}
SSL=${SSL:-nossl}
TOPOLOGY=${TOPOLOGY:-server}
LOAD_BALANCER=${LOAD_BALANCER}
STORAGE_ENGINE=${STORAGE_ENGINE}
REQUIRE_API_VERSION=${REQUIRE_API_VERSION}
DISABLE_TEST_COMMANDS=${DISABLE_TEST_COMMANDS}
MONGODB_VERSION=${MONGODB_VERSION:-latest}
MONGODB_DOWNLOAD_URL=${MONGODB_DOWNLOAD_URL}
ORCHESTRATION_FILE=${ORCHESTRATION_FILE}

DL_START=$(date +%s)
DIR=$(dirname $0)
# Functions to fetch MongoDB binaries
. $DIR/download-mongodb.sh

get_distro
if [ -z "$MONGODB_SKIP_DOWNLOAD" ]; then
  if [ -z "$MONGODB_DOWNLOAD_URL" ]; then
      get_mongodb_download_url_for "$DISTRO" "$MONGODB_VERSION"
  else
    # Even though we have the MONGODB_DOWNLOAD_URL, we still call this to get the proper EXTRACT variable
    get_mongodb_download_url_for "$DISTRO"
  fi
    download_and_extract "$MONGODB_DOWNLOAD_URL" "$EXTRACT" "$MONGOSH_DOWNLOAD_URL" "$EXTRACT_MONGOSH"
  fi
fi

DL_END=$(date +%s)
MO_START=$(date +%s)

# If no orchestration file was specified, build up the name based on configuration parameters.
if [ -z "$ORCHESTRATION_FILE" ]; then
  ORCHESTRATION_FILE="basic"
  if [ "$AUTH" = "auth" ]; then
    ORCHESTRATION_FILE="auth"
  fi

  if [ "$SSL" != "nossl" ]; then
    ORCHESTRATION_FILE="${ORCHESTRATION_FILE}-ssl"
  fi

  if [ -n "$LOAD_BALANCER" ]; then
    ORCHESTRATION_FILE="${ORCHESTRATION_FILE}-load-balancer"
  fi

  # disableTestCommands files do not exist for different auth or ssl modes.
  if [ ! -z "$DISABLE_TEST_COMMANDS" ]; then
    ORCHESTRATION_FILE="disableTestCommands"
  fi

  # Storage engine config files do not exist for different auth or ssl modes.
  if [ ! -z "$STORAGE_ENGINE" ]; then
    ORCHESTRATION_FILE="$STORAGE_ENGINE"
  fi

  ORCHESTRATION_FILE="${ORCHESTRATION_FILE}.json"
fi

# Allow projects to override orchestration configs
ORCHESTRATION_FILE="configs/${TOPOLOGY}s/${ORCHESTRATION_FILE}"

if [ -f "$PROJECT_ORCHESTRATION_HOME/$ORCHESTRATION_FILE" ]; then
  export ORCHESTRATION_FILE="$PROJECT_ORCHESTRATION_HOME/$ORCHESTRATION_FILE"
elif [ -f "$MONGO_ORCHESTRATION_HOME/$ORCHESTRATION_FILE" ]; then
  export ORCHESTRATION_FILE="$MONGO_ORCHESTRATION_HOME/$ORCHESTRATION_FILE"
else
  echo "Could not find orchestration file $ORCHESTRATION_FILE (checked in $PROJECT_ORCHESTRATION_HOME and $MONGO_ORCHESTRATION_HOME)"
  exit 1
fi

perl -p -i -e "s|ABSOLUTE_PATH_REPLACEMENT_TOKEN|${DRIVERS_TOOLS}|g" $ORCHESTRATION_FILE

export ORCHESTRATION_URL="http://localhost:8889/v1/${TOPOLOGY}s"

# Start mongo-orchestration
bash $DIR/start-orchestration.sh "$MONGO_ORCHESTRATION_HOME"

pwd
if ! curl --silent --show-error --data @"$ORCHESTRATION_FILE" "$ORCHESTRATION_URL" --max-time 600 --fail -o tmp.json; then
  echo Failed to start cluster, see $MONGO_ORCHESTRATION_HOME/out.log:
  cat $MONGO_ORCHESTRATION_HOME/out.log
  echo Failed to start cluster, see $MONGO_ORCHESTRATION_HOME/server.log:
  cat $MONGO_ORCHESTRATION_HOME/server.log
  exit 1
fi
cat tmp.json
URI=$(python3 -c 'import json; j=json.load(open("tmp.json")); print(j["mongodb_auth_uri" if "mongodb_auth_uri" in j else "mongodb_uri"])' | tr -d '\r')
echo 'MONGODB_URI: "'$URI'"' > mo-expansion.yml
echo $URI > $DRIVERS_TOOLS/uri.txt
echo "Cluster URI: $URI"
# Define SKIP_CRYPT_SHARED=1 to skip downloading crypt_shared. This is useful for platforms that have a
# server release but don't ship a corresponding crypt_shared release, like Amazon 2018.
if [ -z "${SKIP_CRYPT_SHARED:-}" ]; then
  if [ -z "$MONGO_CRYPT_SHARED_DOWNLOAD_URL" ]; then
    echo "There is no crypt_shared library for distro='$DISTRO' and version='$MONGODB_VERSION'".
  else
    echo "Downloading crypt_shared package from $MONGO_CRYPT_SHARED_DOWNLOAD_URL"
    download_and_extract_crypt_shared "$MONGO_CRYPT_SHARED_DOWNLOAD_URL" "$EXTRACT" CRYPT_SHARED_LIB_PATH
    echo "CRYPT_SHARED_LIB_PATH:" $CRYPT_SHARED_LIB_PATH
    if [ -z $CRYPT_SHARED_LIB_PATH ]; then
      echo "CRYPT_SHARED_LIB_PATH must be assigned, but wasn't" 1>&2 # write to stderr"
      exit 1
    fi
  cat <<EOT >> mo-expansion.yml
CRYPT_SHARED_LIB_PATH: "$CRYPT_SHARED_LIB_PATH"
EOT
  fi
fi

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

# Set the requireApiVersion parameter
if [ ! -z "$REQUIRE_API_VERSION" ]; then
  mongosh $URI $MONGO_ORCHESTRATION_HOME/require-api-version.js
fi
