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
#   SKIP_CRYPT_SHARED      Set to a non-empty string to skip downloading crypt_shared
#   MONGODB_BINARIES       Set to a non-empty string to set the path to the MONGODB_BINARIES for mongo orchestration.
#   INSTALL_LEGACY_SHELL   Set to a non-empty string to install the legacy mongo shell.

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
MONGODB_BINARIES=${MONGODB_BINARIES:-}
INSTALL_LEGACY_SHELL=${INSTALL_LEGACY_SHELL:-}

DL_START=$(date +%s)
# See https://stackoverflow.com/questions/35006457/choosing-between-0-and-bash-source/35006505#35006505
# Why we need this syntax when sh is not aliased to bash (this script must be able to be called from sh)
SCRIPT_DIR=$(dirname ${BASH_SOURCE:-$0})
. $SCRIPT_DIR/handle-paths.sh

# Functions to fetch MongoDB binaries.
. $SCRIPT_DIR/download-mongodb.sh

# To continue supporting `sh run-orchestration.sh` for backwards-compatibility,
# explicitly invoke Bash as a subshell here when running `find_python3`.
echo "Finding Python3 binary..."
PYTHON="$(bash -c ". $SCRIPT_DIR/find-python3.sh && find_python3 2>/dev/null")"
echo "Finding Python3 binary... done."

# Fix orchestration path.
if [[ "$(uname -s)" == CYGWIN* ]]; then
  MONGO_ORCHESTRATION_HOME=$(cygpath -m $MONGO_ORCHESTRATION_HOME)
fi

# Set up the mongo orchestration config.
if [ -n "${MONGODB_BINARIES}" ]; then
  # Fix binaries path.
  if [[ "$(uname -s)" == CYGWIN* ]]; then
    MONGODB_BINARIES=$(cygpath -m $MONGODB_BINARIES)
  fi
  echo "{ \"releases\": { \"default\": \"$MONGODB_BINARIES\" }}" > $MONGO_ORCHESTRATION_HOME/orchestration.config
fi

# Copy client certificate because symlinks do not work on Windows.
cp ${DRIVERS_TOOLS}/.evergreen/x509gen/client.pem ${MONGO_ORCHESTRATION_HOME}/lib/client.pem || true

get_distro
if [ -z "$MONGODB_DOWNLOAD_URL" ]; then
    get_mongodb_download_url_for "$DISTRO" "$MONGODB_VERSION"
else
  # Even though we have the MONGODB_DOWNLOAD_URL, we still call this to get the proper EXTRACT variable
  get_mongodb_download_url_for "$DISTRO"
fi
download_and_extract "$MONGODB_DOWNLOAD_URL" "$EXTRACT" "$MONGOSH_DOWNLOAD_URL" "$EXTRACT_MONGOSH"

# Write the crypt shared path to the expansion file if given.
if [ -n "$CRYPT_SHARED_LIB_PATH" ]; then
    cat <<EOT >> mo-expansion.yml
CRYPT_SHARED_LIB_PATH: "$CRYPT_SHARED_LIB_PATH"
EOT

  cat <<EOT >> mo-expansion.sh
export CRYPT_SHARED_LIB_PATH="$CRYPT_SHARED_LIB_PATH"
EOT
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

# Handle absolute path.
perl -p -i -e "s|ABSOLUTE_PATH_REPLACEMENT_TOKEN|${DRIVERS_TOOLS}|g" $ORCHESTRATION_FILE

# Docker does not enable ipv6 by default.
# https://docs.docker.com/config/daemon/ipv6/
# We also need to use 0.0.0.0 instead of 127.0.0.1
if [ -n "$DOCKER_RUNNING" ]; then
  cp $ORCHESTRATION_FILE /root/config.json
  export ORCHESTRATION_FILE=/root/config.json
  sed -i "s/\"ipv6\": true,/\"ipv6\": false,/g" $ORCHESTRATION_FILE
  sed -i "s/\"127\.0\.0\.1\,/\"0.0.0.0\,/g" $ORCHESTRATION_FILE
fi

export ORCHESTRATION_URL="http://localhost:8889/v1/${TOPOLOGY}s"

# Start mongo-orchestration
PYTHON="${PYTHON:?}" bash $SCRIPT_DIR/start-orchestration.sh "$MONGO_ORCHESTRATION_HOME"

if ! curl --silent --show-error --data @"$ORCHESTRATION_FILE" "$ORCHESTRATION_URL" --max-time 600 --fail -o tmp.json; then
  echo Failed to start cluster, see $MONGO_ORCHESTRATION_HOME/out.log:
  cat $MONGO_ORCHESTRATION_HOME/out.log
  echo Failed to start cluster, see $MONGO_ORCHESTRATION_HOME/server.log:
  cat $MONGO_ORCHESTRATION_HOME/server.log
  exit 1
fi
cat tmp.json

URI=$(${PYTHON:?} -c 'import json; j=json.load(open("tmp.json")); print(j["mongodb_auth_uri" if "mongodb_auth_uri" in j else "mongodb_uri"])' | tr -d '\r')
echo 'MONGODB_URI: "'$URI'"' >> mo-expansion.yml
echo $URI > $DRIVERS_TOOLS/uri.txt
printf "\nCluster URI: %s\n" "$URI"

MO_END=$(date +%s)
MO_ELAPSED=$(expr $MO_END - $MO_START)
DL_ELAPSED=$(expr $DL_END - $DL_START)
cat <<EOT >$DRIVERS_TOOLS/results.json
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
