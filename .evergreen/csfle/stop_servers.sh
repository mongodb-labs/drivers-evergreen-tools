#!/bin/bash

# Clean up CSFLE kmip servers
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR
if [ -f "kmip_pids.pid" ]; then
  < kmip_pids.pid xargs kill -9
  rm kmip_pids.pid
fi
popd
