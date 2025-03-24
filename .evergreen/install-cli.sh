#!/usr/bin/env bash
# Install the drivers orchestration scripts.

set -eu

if [ -z "$BASH" ]; then
  echo "install-cli.sh must be run in a Bash shell!" 1>&2
  return 1
fi

TARGET_DIR="${1:?"must give a target directory!"}"

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
  export PATH
  case "${OSTYPE:?}" in
  cygwin)
    PATH="/cygdrive/c/Python/Current:${PATH:-}"
    ;;
  darwin*)
    PATH="/Library/Frameworks/Python.Framework/Versions/Current/bin:${PATH:-}"
    ;;
  *)
    PATH="/opt/python/Current/bin:${PATH:-}"
    ;;
  esac
fi

# Only ensure a Python binary when not already specified for uv.
if [ -z "${UV_PYTHON:-}" ]; then
   . ./find-python3.sh

  echo "Ensuring python binary..."
  UV_PYTHON="$(ensure_python3 2>/dev/null)"
  if [ -z "${UV_PYTHON}" ]; then
    # For debug purposes
    find_python3
    exit 1
  fi
  echo "Ensuring python binary... done."
fi
export UV_PYTHON

if command -V uv 2>/dev/null; then
  # Ensure there is a venv available for backward compatibility.
  uv venv venv
else
  # If uv is still not available, we need a venv.
  . ./venv-utils.sh

  # Create and activate `venv` via `venvcreate` or `venvactivate`.
  if [ ! -d "$SCRIPT_DIR/venv" ]; then
    echo "Creating virtual environment 'venv'..."
    venvcreate "${UV_PYTHON:?}" venv
    echo "Creating virtual environment 'venv'... done."
  else
    venvactivate venv
  fi

  # Install uv into the newly created venv.
  UV_UNMANAGED_INSTALL=1 python -m pip install -q --force-reinstall uv

  # Ensure a working uv binary is present.
  command -V uv
fi

[[ -d venv ]] # venv should exist by this point.

pushd "$TARGET_DIR" > /dev/null

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
  UV_TOOL_BIN_DIR=$(pwd) uv tool install -q ${EXTRA_ARGS} --with certifi --force --editable .
fi

popd > /dev/null
popd > /dev/null
