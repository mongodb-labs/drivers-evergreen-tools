#!/usr/bin/env bash
# Handle setup for orchestration

set -o errexit
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPT_DIR:?}/../handle-paths.sh"

if [ -n "${CI:-}" ]; then
  (
    cd $SCRIPT_DIR/..
    bash ./install-node.sh
    source ./init-node-and-npm-env.sh

    # Use the standard registry.
    npm config set -L project registry "https://registry.npmjs.org"
  )
fi

set -x

if [ ! -f $SCRIPT_DIR/index.js ]; then
  (
    cd $SCRIPT_DIR
    npm install .
    npm run compile
    # TODO: remove after installing runner from npm registry.
    cd node_modules/mongodb-runner
    npm install .
    npm run compile
  )
fi
