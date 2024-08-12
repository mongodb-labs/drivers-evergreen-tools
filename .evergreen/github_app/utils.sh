#!/usr/bin/env bash
set -eu

function bootstrap() {
    SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
    . $SCRIPT_DIR/../handle-paths.sh
    pushd $SCRIPT_DIR > /dev/null

    # Bootstrap the secrets.
    . ./setup-secrets.sh

    # Install node and activate it.
    bash ../install-node.sh
    source ../init-node-and-npm-env.sh

    # Install the app.
    npm install

    popd > /dev/null
}
