#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -f $SCRIPT_DIR/secrets-export.sh ]; then
  echo "Sourcing secrets"
  source $SCRIPT_DIR/secrets-export.sh
fi

bash $SCRIPT_DIR/../delete-pod.sh eks default
