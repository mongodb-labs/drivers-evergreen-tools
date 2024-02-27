#!/usr/bin/env bash
set -o errexit  # Exit the script with error if any of the commands fail
set -x

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Bootstrap the secrets.
. ../secrets_handling/setup-secrets.sh drivers/comment-bot

# Install node and activate it.
bash ../install-node.sh
source ../init-node-and-npm-env.sh

# Install and run the app.
set -x
npm install
node apply-labels.mjs "$@"
popd
