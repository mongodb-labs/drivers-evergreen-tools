#!/usr/bin/env bash

# Test happy eyeballs scripts for different inputs.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/../happy_eyeballs

# Start the default server.
bash ./setup.sh

# Run the client.
. ../find-python3.sh
PYTHON=$(ensure_python3 2>/dev/null)
$PYTHON client.py

# Tear down the server
bash ./teardown.sh

# Start the server on another port
bash ./setup.sh -c 10037

# Run the client.
. ../find-python3.sh
PYTHON=$(ensure_python3 2>/dev/null)
$PYTHON client.py -c 10037

# Tear down the server.
bash ./teardown.sh -c 10037

popd
make -C ${DRIVERS_TOOLS} test
