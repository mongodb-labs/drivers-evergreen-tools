#!/bin/bash
set -o errexit  # Exit the script with error if any of the commands fail

bash $DRIVERS_TOOLS/.evergreen/auth_aws/setup_secrets.sh drivers/comment-bot
npm install
source secrets-export.sh
node create_or_modify_comment.js "$@"
