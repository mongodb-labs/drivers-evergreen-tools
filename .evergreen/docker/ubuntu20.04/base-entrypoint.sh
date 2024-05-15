#!/usr/bin/env bash
set -eu

# Clear out files that might interfere.
rm -f $DRIVERS_TOOLS/results.json
rm -rf /tmp/mongo*
rm -f $DRIVERS_TOOLS/.env

# Start the server.
cd $DRIVERS_TOOLS/.evergreen
bash run-orchestration.sh

# Preserve host permissions of files we have created.
cd $DRIVERS_TOOLS
files=(results.json uri.txt .evergreen/mongo_crypt_v1.so .evergreen/mo-expansion.yml)
chown --reference=action.yml "${files[@]}"
chmod --reference=action.yml "${files[@]}"

echo "Server started!"
