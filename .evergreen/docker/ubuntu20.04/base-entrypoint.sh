#!/usr/bin/env bash
set -eu

# Start the server.
cd $DRIVERS_TOOLS
make run-server

echo "Server started!"
