#!/usr/bin/env bash
set -o errexit  # Exit the script with error if any of the commands fail
set -x

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Bootstrap the secrets.
bash $SCRIPT_DIR/../auth_aws/setup_secrets.sh drivers/comment-bot
source secrets-export.sh

# Install node and activate it.
bash $SCRIPT_DIR/../install-node.sh
source $SCRIPT_DIR/../init-node-and-npm-env.sh

# Install and run the app.
set -x
npm install
node create_or_modify_comment.mjs "$@"
popd
