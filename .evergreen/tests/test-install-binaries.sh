#!/usr/bin/env bash
set -eu -o pipefail

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/..

# Ensure uv is available, then resolve the interpreter it would use.
. ./ensure-uv.sh
ensure_uv || exit 1
PYTHON_BINARY=$(uv python find)
PATH="$(dirname "$PYTHON_BINARY"):$PATH"

./install-node.sh
. ./init-node-and-npm-env.sh
if "$PYTHON_BINARY" -c "
import sys
sys.path.insert(0, 'orchestration')
from mongodb_runner import _mongodb_runner_supported
sys.exit(0 if _mongodb_runner_supported() else 1)
"; then
  # Invoke node directly on the installed runner.js rather than the npm .bin
  # shim, which can fail on Windows (CRLF shebang line or missing interpreter).
  RUNNER_JS=$("$PYTHON_BINARY" -c "
import shutil
import sys
sys.path.insert(0, 'orchestration')
from mongodb_runner import _MR_VERSION, TMPDIR, _install_mongodb_runner, _normalize_path
shutil.rmtree(TMPDIR / f'mongodb-runner-{_MR_VERSION}', ignore_errors=True)
runner_bin = _install_mongodb_runner()
runner_js = runner_bin.parent.parent / 'mongodb-runner' / 'bin' / 'runner.js'
print(_normalize_path(runner_js))
" | tr -d '\r')
  node "$RUNNER_JS" --help
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
