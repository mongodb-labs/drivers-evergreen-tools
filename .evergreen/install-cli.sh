#!/usr/bin/env bash
# Install the drivers orchestration scripts.

set -eu

if [ -z "$BASH" ]; then
  echo "install-cli.sh must be run in a Bash shell!" 1>&2
  return 1
fi

if [ -z "${1:-}" ]; then
  echo "Must give a target directory!"
fi

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

pushd $SCRIPT_DIR > /dev/null

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
else
  venvactivate venv
fi
python -m pip install -q uv

pushd $1 > /dev/null

# On Windows, we have to do a bit of path manipulation.
if [ "Windows_NT" == "${OS:-}" ]; then
  TMP_DIR=$(cygpath -m "$(mktemp -d)")
  PATH="$SCRIPT_DIR/venv/Scripts:$PATH"
  UV_TOOL_BIN_DIR=${TMP_DIR} uv tool install --force --editable .
  filenames=$(ls ${TMP_DIR})
  for filename in $filenames; do
    mv $TMP_DIR/$filename "$1/${filename//.exe/}"
  done
  rm -rf $TMP_DIR
else
  UV_TOOL_BIN_DIR=$(pwd) uv tool install -q --python "$(which python)" --force --editable .
fi

popd > /dev/null
popd > /dev/null
