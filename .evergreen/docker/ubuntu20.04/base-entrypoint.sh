#!/usr/bin/env bash
set -eu

# Start the server.
cd $DRIVERS_TOOLS
make run-server

# Preserve host permissions of files we have created.
cd $DRIVERS_TOOLS
files=(results.json uri.txt .evergreen/mongo_crypt_v1.so .evergreen/mo-expansion.yml)
chown --reference=action.yml "${files[@]}"
chmod --reference=action.yml "${files[@]}"

echo "Server started!"
