#!/usr/bin/env bash
set -eu

function bootstrap() {
    SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
    . $SCRIPT_DIR/../handle-paths.sh
    pushd $SCRIPT_DIR > /dev/null

    # Bootstrap the secrets.
    . ./setup-secrets.sh ${1:-}

    # Install node and activate it.
    bash ../install-node.sh
    source ../init-node-and-npm-env.sh

    # Use the standard registry.
    npm config set -L project registry "https://registry.npmjs.org"

    # Install the app.
    npm install

    popd > /dev/null
}
