#!/usr/bin/env bash
# Install the drivers orchestration scripts.

set -eux

if [ -z "$BASH" ]; then
  echo "install-cli.sh must be run in a Bash shell!" 1>&2
  return 1
fi

if [ -z "${1:-}" ]; then
  echo "Must give a target directory!"
  exit 1
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

# If uv is not on path, try see if it is available from the Python toolchain.
if ! command -v uv >/dev/null; then
  _bin_path=""
  if [ "Windows_NT" == "${OS:-}" ]; then
    _bin_path="/cygdrive/c/Python/Current"
  elif [ "$(uname -s)" != "Darwin" ]; then
    _bin_path="/Library/Frameworks/Python.Framework/Versions/Current"
  else
    _bin_path="/opt/python/Current"
  fi
  if [ -d "${_bin_path}" ]; then
    export PATH="${_bin_path}:$PATH"
  fi
fi

# If uv is still not available, we need a venv.
if ! command -v uv >/dev/null; then
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
fi

# If uv is still not available, we need to install it into the venv.
if ! command -v uv >/dev/null; then
  UV_UNMANAGED_INSTALL=1 python -m pip install -q --force-reinstall uv
fi

command -V uv # Ensure a working uv binary is present.

# Ensure there is a venv available for backwards compatibility.
if [ ! -d venv ]; then
  uv venv venv
fi

# Store paths to binaries for use outside of current working directory.
python_binary="$(uv run python -c 'import sys;print(sys.executable)')"

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
  UV_TOOL_BIN_DIR=${TMP_DIR} uv tool install ${EXTRA_ARGS} --with certifi --force --editable .
  filenames=$(ls ${TMP_DIR})
  for filename in $filenames; do
    mv $TMP_DIR/$filename "$1/${filename//.exe/}"
  done
  rm -rf $TMP_DIR
else
  UV_TOOL_BIN_DIR=$(pwd) uv tool install -q ${EXTRA_ARGS} --python "${python_binary}" --with certifi --force --editable .
fi

popd > /dev/null
popd > /dev/null
