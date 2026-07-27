#!/usr/bin/env bash

# Test aws setup function for different inputs.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/..
DOWNLOAD_DIR=$SCRIPT_DIR/dl_test
bash install-cli.sh .
./mongosh-dl --version 2.1.1 --out ${DOWNLOAD_DIR}/bin --strip-path-components 2 --retries 5
popd

pushd $SCRIPT_DIR/../atlas_data_lake
bash ./setup.sh
source secrets-export.sh
export MONGODB_BINARIES="${DOWNLOAD_DIR}/bin"
export MONGODB_URI="mongodb://$ADL_USERNAME:$ADL_PASSWORD@localhost:27017"
. "${DRIVERS_TOOLS}/.evergreen/check-connection.sh"
bash ./teardown.sh
popd

rm -rf "${SCRIPT_DIR:?}/${DOWNLOAD_DIR}"

make -C ${DRIVERS_TOOLS} test
