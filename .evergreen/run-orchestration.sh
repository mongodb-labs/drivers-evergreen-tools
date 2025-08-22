#!/usr/bin/env bash
# shellcheck shell=sh
set -eu

# Supported environment variables:
#   AUTH                   Set to "auth" to enable authentication. Defaults to "noauth"
#   SSL                    Set to "yes" to enable SSL. Defaults to "nossl"
#   TOPOLOGY               Set to "server", "replica_set", or "sharded_cluster". Defaults to "server" (i.e. standalone).
#   MONGODB_VERSION        Set the MongoDB version to use. Defaults to "latest".
#   MONGODB_DOWNLOAD_URL   Set the MongoDB download URL to use for download-mongodb.sh.
#   ORCHESTRATION_FILE     Set the <topology>/<orchestration_file>.json configuration.
#   STORAGE_ENGINE         Set to a non-empty string to use the <topology>/<storage_engine>.json configuration (e.g. STORAGE_ENGINE=inmemory).
#   REQUIRE_API_VERSION    Set to a non-empty string to set the requireApiVersion parameter. Currently only supported for standalone servers.
#   DISABLE_TEST_COMMANDS  Set to a non-empty string to use the <topology>/disableTestCommands.json configuration (e.g. DISABLE_TEST_COMMANDS=1).
#   SKIP_CRYPT_SHARED      Set to a non-empty string to skip downloading crypt_shared
#   LOAD_BALANCER          Set to a non-empty string to enable load balancer. Only supported for sharded clusters.
#   AUTH_AWS               Set to a non-empty string to enable MONGODB-AWS authentication.
#   PYTHON                 Set the Python binary to use.
#   LOCAL_ATLAS            Set to use mongodb-atlas-local to start the server.
#   INSTALL_LEGACY_SHELL   Set to a non-empty string to install the legacy mongo shell.
#   TLS_PEM_KEY_FILE       Set a .pem file that contains the TLS certificate and key for the server
#   TLS_CA_FILE            Set a .pem file that contains the root certificate chain for the server

# The following variables affect the mongo-orchestration server:
#  MONGO_ORCHESTRATION_HOME  Set the path where the files used by mongo-orchestration will be located.
#  MONGODB_BINARIES          Set the path to the MONGODB_BINARIES for mongo-orchestration.
#  TLS_CERT_KEY_FILE         Set a .pem file to be used as the tlsCertificateKeyFile option in mongo-orchestration.

# See https://stackoverflow.com/questions/35006457/choosing-between-0-and-bash-source/35006505#35006505
# Why we need this syntax when sh is not aliased to bash (this script must be able to be called from sh)
# shellcheck disable=SC3028
SCRIPT_DIR=$(dirname ${BASH_SOURCE:-$0})
. $SCRIPT_DIR/handle-paths.sh

# Ensure the CLIs are up to date.
bash $SCRIPT_DIR/orchestration/setup.sh

$SCRIPT_DIR/orchestration/drivers-orchestration run "$@"
