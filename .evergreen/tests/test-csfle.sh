#!/usr/bin/env bash

# Test csfle
set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/../csfle

# Test with default python
PYTHON_BINARY=$(bash -c ". $SCRIPT_DIR/../find-python3.sh && ensure_python3 2>/dev/null")
export PYTHON_BINARY

function run_test() {
  bash ./setup.sh
  bash ./teardown.sh
  rm -rf kmstlsvenv
}
run_test


# Test with supported pythons
pythons="3.8 3.9 3.10 3.11 3.12 3.13"
for python in $pythons; do
  if [ "$(uname -s)" = "Darwin" ]; then
    PYTHON_BINARY="/Library/Frameworks/Python.Framework/Versions/$python/bin/python3"
  elif [[ "$(uname -s)" == CYGWIN* ]]; then
     PYTHON_BINARY="C:/python/Python3${python//.}/bin/python"
  else
    PYTHON_BINARY="/opt/python/$python/bin/python3"
  fi
  export PYTHON_BINARY
  run_test
done
