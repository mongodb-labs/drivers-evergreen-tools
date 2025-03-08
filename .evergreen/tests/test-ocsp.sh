#!/usr/bin/env bash

# Test aws setup function for different inputs.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh


if [[ "$(uname -s)" == CYGWIN* ]]; then
  ORCHESTRATION_FILE="rsa-basic-tls-ocsp-disableStapling.json"
  OCSP_SERVER_TYPE="revoked"
  URI_OPTIONS="tls=true&tlsInsecure=true"
  OCSP_ALGORITHM="rsa"
elif [[ $(uname -s) = "Darwin" ]]; then
  ORCHESTRATION_FILE="rsa-basic-tls-ocsp-disableStapling.json"
  OCSP_SERVER_TYPE="valid"
  URI_OPTIONS="tls=true"
  OCSP_ALGORITHM="rsa"
else
  ORCHESTRATION_FILE="ecdsa-basic-tls-ocsp-mustStaple.json"
  OCSP_SERVER_TYPE="valid-delegate"
  URI_OPTIONS="tls=true"
  OCSP_ALGORITHM="ecdsa"
fi
export ORCHESTRATION_FILE
export OCSP_SERVER_TYPE
export OCSP_ALGORITHM

# Start a MongoDB server with ocsp enabled.
SSL="ssl" make -C ${DRIVERS_TOOLS} run-server

pushd $SCRIPT_DIR/../ocsp

# Start the ocsp server.
bash ./setup.sh

# Connect to the MongoDB server.
echo "Connecting to server..."
TLS_OPTS=("--tls --tlsCertificateKeyFile \"${DRIVERS_TOOLS}/.evergreen/ocsp/${OCSP_ALGORITHM}/server.pem\"")
TLS_OPTS+=("--tlsCAFile \"${DRIVERS_TOOLS}/.evergreen/ocsp/${OCSP_ALGORITHM}/ca.pem\"")
$MONGODB_BINARIES/mongosh "mongodb://localhost:27017/&${URI_OPTIONS}" "${TLS_OPTS[@]}" --eval "db.runCommand({\"ping\":1})"
echo "Connecting to server... done."

bash ./teardown.sh

popd

make -C ${DRIVERS_TOOLS} stop-server
make -C ${DRIVERS_TOOLS} test
