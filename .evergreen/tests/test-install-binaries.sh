#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/..

if [ -z "${SKIP_NODE:-}" ]; then
  ./install-node.sh
fi

./install-rust.sh

if [ $OS != "Windows_NT" ]; then
  # Add a suitable python3 to the path.
  PYTHON_BINARY=$(bash -c ". $SCRIPT_DIR/../find-python3.sh && ensure_python3 2>/dev/null")
  PATH="$(dirname $PYTHON_BINARY):$PATH"
  case $(uname -m) in
    aarch64 | x86_64 | arm64)
      . ./ensure-binary.sh gcloud
      gcloud --version
      . ./ensure-binary.sh kubectl
      which kubectl
      ;;
  esac
fi

popd
make -C ${DRIVERS_TOOLS} test
