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
# Exit 0: supported. Exit 1: genuinely unsupported here, skip below. Exit 2: the
# committed pin itself is broken, which must fail the task rather than look like
# a platform skip -- _mongodb_runner_supported raises for exactly that case.
"$PYTHON_BINARY" -c "
import sys
sys.path.insert(0, 'orchestration')
try:
    from mongodb_runner import _mongodb_runner_supported
    supported = _mongodb_runner_supported('8.0')
except Exception as exc:
    print(f'mongodb-runner pin is broken: {exc}', file=sys.stderr)
    sys.exit(2)
sys.exit(0 if supported else 1)
" && support_status=0 || support_status=$?
if [ "$support_status" -eq 0 ]; then
  # Invoke node directly on the installed runner.js rather than the npm .bin
  # shim, which can fail on Windows (CRLF shebang line or missing interpreter).
  RUNNER_JS=$("$PYTHON_BINARY" -c "
import shutil
import sys
sys.path.insert(0, 'orchestration')
from mongodb_runner import TMPDIR, _install_mongodb_runner, _normalize_path
# Clear every cached pin install so this is a fresh install, not just the one
# '8.0' resolves to. TMPDIR also doubles as mongodb-runner's runnerDir, so the
# glob is scoped to install directory names rather than the whole prefix.
for path in TMPDIR.glob('mongodb-runner-*-mongodb-*'):
    shutil.rmtree(path, ignore_errors=True)
runner_bin = _install_mongodb_runner('8.0')
runner_js = runner_bin.parent.parent / 'mongodb-runner' / 'bin' / 'runner.js'
print(_normalize_path(runner_js))
" | tr -d '\r')
  node "$RUNNER_JS" --help
elif [ "$support_status" -eq 1 ]; then
  echo "mongodb-runner is not supported on this platform; skipping check"
else
  echo "mongodb-runner support check failed unexpectedly (exit $support_status)"
  exit 1
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
