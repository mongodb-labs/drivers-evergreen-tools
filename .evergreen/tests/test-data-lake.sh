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
${DOWNLOAD_DIR}/bin/mongosh "mongodb://$ADL_USERNAME:$ADL_PASSWORD@localhost:27017" --eval "db.runCommand({\"ping\":1})"
bash ./teardown.sh
popd

rm -rf "${SCRIPT_DIR:?}/${DOWNLOAD_DIR}"

make -C ${DRIVERS_TOOLS} test
