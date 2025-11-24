#!/usr/bin/env bash

# Test usage of start-server.sh
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
. $SCRIPT_DIR/../find-python3.sh

pushd $SCRIPT_DIR/.. > /dev/null

# Connect to the MongoDB server using tls
# shellcheck disable=SC2120
function connect_mongodb() {
  local use_tls=false

  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ssl) use_tls=true; shift ;;
      *) echo "Unknown option: $1"; return 1 ;;
    esac
  done

  URI="mongodb://localhost:27017/?directConnection=true&serverSelectionTimeoutMS=10000"
  local TLS_OPTS=()
  if [[ "$use_tls" == "true" ]]; then
    TLS_OPTS+=("--tls" "--tlsCertificateKeyFile" "${DRIVERS_TOOLS}/.evergreen/x509gen/server.pem")
    TLS_OPTS+=("--tlsCAFile" "${DRIVERS_TOOLS}/.evergreen/x509gen/ca.pem")
  fi
  echo "Connecting to server..."
  # shellcheck disable=SC2068
  $MONGODB_BINARIES/mongosh "$URI" ${TLS_OPTS[@]:-} --eval "db.runCommand({\"ping\":1})"
  echo "Connecting to server... done."
}

# Test for default, then test cli options.
bash ./run-server.sh
connect_mongodb

bash ./run-server.sh --topology server --auth
connect_mongodb

# bash ./run-server.sh --version 7.0 --topology replica_set --ssl
# connect_mongodb --ssl

# bash ./run-server.sh --version latest --topology sharded_cluster --auth --ssl
# connect_mongodb --ssl

# Ensure that we can use a downloaded mongodb directory.
DOWNLOAD_DIR=mongodl_test
rm -rf ${DOWNLOAD_DIR}
bash install-cli.sh "$(pwd)/orchestration"
PYTHON="$(ensure_python3 2>/dev/null)"
$PYTHON mongodl.py --edition enterprise --version 7.0 --component archive --out ${DOWNLOAD_DIR} --strip-path-components 2 --retries 5
bash ./run-server.sh --existing-binaries-dir=${DOWNLOAD_DIR}
${DOWNLOAD_DIR}/mongod --version | grep v7.0

if [ "${1:-}" == "partial" ]; then
  popd > /dev/null
  make -C ${DRIVERS_TOOLS} test
  exit 0
fi

for version in rapid 8.0 6.0 5.0 4.4 4.2
do
  bash ./run-server.sh --version "$version"
  connect_mongodb
done

popd > /dev/null
make -C ${DRIVERS_TOOLS} test
