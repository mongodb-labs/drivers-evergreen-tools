#!/usr/bin/env bash
set -eu

# Remove the virtual env
rm -rf $DRIVERS_TOOLS/.evergreen/venv || true

# Start the server.
cd $DRIVERS_TOOLS
make run-server

# Preserve host permissions of files we have created.
cd $DRIVERS_TOOLS
files=(results.json mo-expansion.yml)
chown --reference=action.yml "${files[@]}"
chmod --reference=action.yml "${files[@]}"

echo "Server started!"
