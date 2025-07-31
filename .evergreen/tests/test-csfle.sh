#!/usr/bin/env bash

# Test csfle
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/../csfle

# Test with default python
PYTHON_BINARY=$(bash -c ". $SCRIPT_DIR/../find-python3.sh && ensure_python3 2>/dev/null")
export PYTHON_BINARY

function run_test() {
  echo "Running csfle test with $PYTHON_BINARY..."
  bash ./setup.sh
  bash ./teardown.sh
  # Bail on Windows due to permission errors trying to remove the kmstlsvenv folder.
  if [[ "$(uname -s)" == CYGWIN* ]]; then
    return 0
  fi
  rm -rf kmstlsvenv
  echo "Running csfle test with $PYTHON_BINARY... done."
}
run_test

# Bail on Windows due to permission errors trying to remove the kmstlsvenv folder.
if [[ "$(uname -s)" == CYGWIN* ]]; then
  exit 0
fi

# Test with supported pythons
pythons="3.9 3.10 3.11 3.12 3.13 3.14"
for python in $pythons; do
  if [ "$(uname -s)" = "Darwin" ]; then
    PYTHON_BINARY="/Library/Frameworks/Python.Framework/Versions/$python/bin/python3"
  else
    PYTHON_BINARY="/opt/python/$python/bin/python3"
  fi
  export PYTHON_BINARY
  run_test
done

popd
