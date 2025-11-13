#!/usr/bin/env bash
# Run orchestration.

set -o errexit

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPT_DIR:?}/../handle-paths.sh"

(
  cd $SCRIPT_DIR
  if [ -n "${CI:-}" ]; then
    source ../init-node-and-npm-env.sh
  fi
  node index.js "$@"
)
