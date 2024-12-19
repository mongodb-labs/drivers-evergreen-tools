#!/usr/bin/env bash
set -eux

# Remove the virtual env and .local directory
rm -rf $DRIVERS_TOOLS/.evergreen/venv || true

# Start the server.
cd $DRIVERS_TOOLS
make run-server

# Preserve host permissions of files we have created.
cd $DRIVERS_TOOLS
files=(results.json uri.txt mo-expansion.yml)
chown --reference=action.yml "${files[@]}"
chmod --reference=action.yml "${files[@]}"

echo "Server started!"
