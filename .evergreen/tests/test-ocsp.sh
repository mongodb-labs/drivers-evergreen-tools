#!/usr/bin/env bash

# Test aws setup function for different inputs.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

if [[ $(uname -s) = "Linux" ]]; then
  ORCHESTRATION_FILE="ecdsa-basic-tls-ocsp-mustStaple.json"
  OCSP_ALGORITHM="ecdsa"
  SERVER_TYPE="valid-delegate"
else
  ORCHESTRATION_FILE="rsa-basic-tls-ocsp-disableStapling.json"
  OCSP_ALGORITHM="rsa"
  SERVER_TYPE="valid"
fi

export ORCHESTRATION_FILE
export OCSP_ALGORITHM
export SERVER_TYPE

. $SCRIPT_DIR/../init-node-and-npm-env.sh

# # Start a MongoDB server with ocsp enabled.
SSL="ssl" make -C ${DRIVERS_TOOLS} run-server

pushd $SCRIPT_DIR/../ocsp

# # Start the ocsp server.
bash ./setup.sh

# Connect to the MongoDB server.
echo "Connecting to server..."
export MONGODB_URI="mongodb://localhost/?serverSelectionTimeoutMS=10000"
export MONGOSH_EXTRA_ARGS="--tls --tlsCertificateKeyFile ${DRIVERS_TOOLS}/.evergreen/ocsp/${OCSP_ALGORITHM}/server.pem --tlsCAFile ${DRIVERS_TOOLS}/.evergreen/ocsp/${OCSP_ALGORITHM}/ca.pem"
bash "${DRIVERS_TOOLS}/.evergreen/check-connection.sh"
echo "Connecting to server... done."

bash ./teardown.sh

popd

make -C ${DRIVERS_TOOLS} stop-server
make -C ${DRIVERS_TOOLS} test
