#!/usr/bin/env bash
set -eux

# Remove the virtual env.
rm -rf $DRIVERS_TOOLS/.evergreen/venv || true

# Start the server.
cd $DRIVERS_TOOLS
make run-server

echo "Server started!"
