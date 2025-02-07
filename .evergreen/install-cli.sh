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

if [ "${DOCKER_RUNNING:-}" == "true" ]; then
  _root_dir=$(mktemp -d)
  UV_CACHE_DIR=$_root_dir/uv-cache
  UV_TOOL_DIR=$_root_dir/uv-tool
fi

. ./venv-utils.sh

if [ ! -d $SCRIPT_DIR/venv ]; then

  . ./find-python3.sh

  echo "Ensuring python binary..."
  PYTHON=$(ensure_python3 2>/dev/null)
  echo "Ensuring python binary... done."

  echo "Creating virtual environment 'venv'..."
  venvcreate "${PYTHON:?}" venv
  echo "Creating virtual environment 'venv'... done."
  python -m pip install -q uv
else
  venvactivate venv
fi

pushd $1 > /dev/null

# Add support for MongoDB 3.6, which was dropped in pymongo 4.11.
EXTRA_ARGS=""
if [ "${MONGODB_VERSION:-latest}" == "3.6" ]; then
  EXTRA_ARGS_ARR=(--with "pymongo<4.11")
  EXTRA_ARGS="${EXTRA_ARGS_ARR[*]}"
fi

# On Windows, we have to do a bit of path manipulation.
if [ "Windows_NT" == "${OS:-}" ]; then
  TMP_DIR=$(cygpath -m "$(mktemp -d)")
  PATH="$SCRIPT_DIR/venv/Scripts:$PATH"
  UV_TOOL_BIN_DIR=${TMP_DIR} python -m uv tool install ${EXTRA_ARGS} --force --editable .
  filenames=$(ls ${TMP_DIR})
  for filename in $filenames; do
    mv $TMP_DIR/$filename "$1/${filename//.exe/}"
  done
  rm -rf $TMP_DIR
else
  UV_TOOL_BIN_DIR=$(pwd) python -m uv tool install -q ${EXTRA_ARGS} --python "$(which python)" --force --editable .
fi

popd > /dev/null
popd > /dev/null
