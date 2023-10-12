#!/bin/bash
set -o errexit  # Exit the script with error if any of the commands fail

DIR=$(dirname $0)
pushd $DIR

# Bootstrap the secrets.
bash $DRIVERS_TOOLS/.evergreen/auth_aws/setup_secrets.sh drivers/comment-bot
source secrets-export.sh

# Bootstrap the appropriate Hydrogen LTS version of node.
# https://github.com/nvm-sh/nvm?tab=readme-ov-file#installing-and-updating
export NVM_DIR=$(pwd)/.nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install lts/hydrogen
nvm use lts/hydrogen

# Install and run the app.
npm install
cat package.json
node create_or_modify_comment.mjs "$@"
popd
