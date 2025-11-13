#!/usr/bin/env bash
# Run orchestration.

set -o errexit

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPT_DIR:?}/../handle-paths.sh"

if [ -n "${CI:-}" ]; then
  (
    cd $SCRIPT_DIR/..
    source ./init-node-and-npm-env.sh
  )
fi

(
  cd $SCRIPT_DIR
  node index.js "$@"
)
