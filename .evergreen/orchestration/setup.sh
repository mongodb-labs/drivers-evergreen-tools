#!/usr/bin/env bash
# Handle setup for orchestration

set -o errexit
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPT_DIR:?}/../handle-paths.sh"


pushd $SCRIPT_DIR
if [ -n "${CI:-}" ]; then

  bash ../install-node.sh
  source ../init-node-and-npm-env.sh

  # Use the standard registry.
  npm config set -L project registry "https://registry.npmjs.org"
fi


npm install .
# TODO: remove after installing runner from npm registry.
pushd node_modules/mongodb-runner
npm install .
npm run compile
popd
npm run compile
popd
