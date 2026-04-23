#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/..

./install-node.sh
. ./init-node-and-npm-env.sh
MR_INSTALL_DIR=$(mktemp -d)
case "$(uname -s)" in
  CYGWIN*) MR_INSTALL_DIR=$(cygpath -m "$MR_INSTALL_DIR") ;;
esac
trap 'rm -rf "$MR_INSTALL_DIR"' EXIT
printf '{"name":"t","version":"1.0.0","dependencies":{"mongodb-runner":"6.7.1"},"overrides":{"@mongodb-js/oidc-mock-provider":"0.13.7"}}' > "$MR_INSTALL_DIR/package.json"
# Use a subshell + cd so npm install uses process.cwd() instead of --prefix,
# which avoids MSYS2/Cygwin path translation issues on Windows.
(cd "$MR_INSTALL_DIR" && npm install --silent)
# Invoke node directly to bypass the .bin/ POSIX shim, which can fail on
# Windows (CRLF shebang line or missing interpreter).
node "$MR_INSTALL_DIR/node_modules/mongodb-runner/bin/runner.js" --help

source ./install-rust.sh
rustup install stable

if [ ${OS:-} != "Windows_NT" ]; then
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
