#!/usr/bin/env bash

# Test aws setup function for different inputs.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

if [[ $(uname -s) = "Linux" ]]; then
  ORCHESTRATION_FILE="ecdsa-basic-tls-ocsp-mustStaple.json"
  OCSP_ALGORITHM="ecdsa"
else
  ORCHESTRATION_FILE="rsa-basic-tls-ocsp-disableStapling.json"
  OCSP_ALGORITHM="rsa"
fi

export ORCHESTRATION_FILE
export OCSP_ALGORITHM

# Start a MongoDB server with ocsp enabled.
SSL="ssl" make -C ${DRIVERS_TOOLS} run-server

pushd $SCRIPT_DIR/../ocsp

# Start the ocsp server.
SERVER_TYPE="valid" bash ./setup.sh

# Connect to the MongoDB server.
echo "Connecting to server..."
TLS_OPTS=("--tls --tlsCertificateKeyFile \"${DRIVERS_TOOLS}/.evergreen/ocsp/${OCSP_ALGORITHM}/server.pem\"")
TLS_OPTS+=("--tlsCAFile \"${DRIVERS_TOOLS}/.evergreen/ocsp/${OCSP_ALGORITHM}/ca.pem\"")
$MONGODB_BINARIES/mongosh "mongodb://localhost:27017" "${TLS_OPTS[@]}" --eval "db.runCommand({\"ping\":1})"
echo "Connecting to server... done."

bash ./teardown.sh

popd

make -C ${DRIVERS_TOOLS} stop-server
make -C ${DRIVERS_TOOLS} test
