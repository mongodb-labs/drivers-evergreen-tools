#!/usr/bin/env bash
# shellcheck shell=sh
set -eu

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
#   PYTHON                 Set to a non-empty string to set the Python binary to use.
#   INSTALL_LEGACY_SHELL   Set to a non-empty string to install the legacy mongo shell.

# See https://stackoverflow.com/questions/35006457/choosing-between-0-and-bash-source/35006505#35006505
# Why we need this syntax when sh is not aliased to bash (this script must be able to be called from sh)
# shellcheck disable=SC3028
SCRIPT_DIR=$(dirname ${BASH_SOURCE:-$0})
. $SCRIPT_DIR/handle-paths.sh

bash $SCRIPT_DIR/orchestration/setup.sh
$SCRIPT_DIR/orchestration/drivers-orchestration run "$@"
