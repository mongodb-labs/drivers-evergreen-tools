#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

rm -f $SCRIPT_DIR/secrets-export.sh
. $SCRIPT_DIR/create-and-setup-vm.sh
