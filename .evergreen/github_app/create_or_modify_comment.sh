#!/bin/bash
set -o errexit  # Exit the script with error if any of the commands fail

DIR=$(dirname $0)
pushd $DIR

# Bootstrap the secrets.
bash $DIR/../auth_aws/setup_secrets.sh drivers/comment-bot
source secrets-export.sh

# Install node and activate it.
bash $DIR/../install-node.sh
. $DIR/../init-node-and-npm-env.sh

# Install and run the app.
npm install
node create_or_modify_comment.mjs "$@"
popd
