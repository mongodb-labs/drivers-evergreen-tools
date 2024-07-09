#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Bootstrap the secrets.
. ../secrets_handling/setup-secrets.sh drivers/comment-bot

# Install node and activate it.
bash ../install-node.sh
source ../init-node-and-npm-env.sh

# Install and run the app.
npm install
node create_or_modify_comment.mjs "$@"
popd
