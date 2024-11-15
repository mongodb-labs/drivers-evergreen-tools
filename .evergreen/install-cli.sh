#!/usr/bin/env bash
# Install the drivers orchestration scripts.

set -eux

if [ -z "$BASH" ]; then
  echo "install-cli.sh must be run in a Bash shell!" 1>&2
  return 1
fi

if [ -z "${1:-}" ]; then
  echo "Must give a target directory!"
fi

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

pushd $SCRIPT_DIR

# Ensure pipx is writing assets to a contained location.
export UV_CACHE_DIR=${DRIVERS_TOOLS}/.local/uv-cache
export UV_TOOL_DIR=${DRIVERS_TOOLS}/.local/uv-tool

. ./venv-utils.sh

if [ ! -d $SCRIPT_DIR/venv ]; then

  . ./find-python3.sh

  echo "Ensuring python binary..."
  PYTHON=$(ensure_python3 2>/dev/null)
  echo "Ensuring python binary... done."

  echo "Creating virtual environment 'venv'..."
  venvcreate "${PYTHON:?}" venv
  echo "Creating virtual environment 'venv'... done."

  python -m pip install uv
else
  venvactivate venv
fi

pushd $1

# On Windows, we have to do a bit more.
if [ "Windows_NT" == "${OS:-}" ]; then
  TMP_DIR="$(mktemp -d)"
  PATH="$SCRIPT_DIR/venv/Scripts:$PATH"
  UV_TOOL_BIN_DIR=$TMP_DIR uv tool install --force --editable .
  pushd $TMP_DIR
  for filename in *; do
    mv $filename "$1/${filename//.exe/}"
  done
  popd
  rm -rf $TMP_DIR
else
  UV_TOOL_BIN_DIR=$(pwd) uv tool install --python "$(which python)" --force --editable .
fi

popd
popd
