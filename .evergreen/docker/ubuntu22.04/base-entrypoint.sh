#!/usr/bin/env bash
set -eu

# Remove the virtual env and any node install.
rm -rf $DRIVERS_TOOLS/.evergreen/venv || true
rm -rf $DRIVERS_TOOLS/.evergreen/node-artifacts || true

# Start the server.
cd $DRIVERS_TOOLS
make run-server

echo "Server started!"
