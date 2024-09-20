#!/usr/bin/env bash
set -ue

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh
pushd $SCRIPT_DIR

export RUSTUP_HOME="${RUSTUP_HOME:-"${DRIVERS_TOOLS}/.rustup"}"
export CARGO_HOME="${CARGO_HOME:-"${DRIVERS_TOOLS}/.cargo"}"
export PATH="${RUSTUP_HOME}/bin:${CARGO_HOME}/bin:$PATH"

# Make sure to use msvc toolchain rather than gnu, which is the default for cygwin
if [ "Windows_NT" == "${OS:-}" ]; then
  export DEFAULT_HOST_OPTIONS='--default-host x86_64-pc-windows-msvc'
  # rustup/cargo need the native Windows paths
  RUSTUP_HOME=$(cygpath ${RUSTUP_HOME} --windows)
  CARGO_HOME=$(cygpath ${CARGO_HOME} --windows)
fi

"$SCRIPT_DIR/retry-with-backoff.sh" curl https://sh.rustup.rs -sSf | sh -s -- -y --no-modify-path ${DEFAULT_HOST_OPTIONS:-}

if [ "Windows_NT" == "${OS:-}" ]; then
  # This file is not created by default on Windows
  echo 'export PATH="$PATH:${CARGO_HOME}/bin"' >>${CARGO_HOME}/env
  echo "export CARGO_NET_GIT_FETCH_WITH_CLI=true" >>${CARGO_HOME}/env
fi

echo "cargo location: $(which cargo)"
echo "cargo version: $(cargo --version)"
echo "rustc location: $(which rustc)"
echo "rustc version: $(rustc --version)"

popd
