#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/..

# The system python3 may be too old (or missing); find a suitable one.
. ./find-python3.sh
PYTHON_BINARY=$(ensure_python3 2>/dev/null)
PATH="$(dirname $PYTHON_BINARY):$PATH"

./install-node.sh
. ./init-node-and-npm-env.sh
if "$PYTHON_BINARY" -c "
import sys
sys.path.insert(0, 'orchestration')
from mongodb_runner import _mongodb_runner_supported
sys.exit(0 if _mongodb_runner_supported() else 1)
"; then
  RUNNER_BIN=$("$PYTHON_BINARY" -c "
import sys
sys.path.insert(0, 'orchestration')
from mongodb_runner import _install_mongodb_runner, _normalize_path
print(_normalize_path(_install_mongodb_runner()))
" | tr -d '\r')
  "$RUNNER_BIN" --help
else
  echo "mongodb-runner is not supported on this platform; skipping check"
fi

source ./install-rust.sh
rustup install stable

if [ ${OS:-} != "Windows_NT" ]; then
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
