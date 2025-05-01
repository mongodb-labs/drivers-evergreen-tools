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

pushd $SCRIPT_DIR >/dev/null

# First ensure we have a python binary.
if [ -z "${DRIVERS_TOOLS_PYTHON:-}" ]; then
   . ./find-python3.sh

  echo "Ensuring python binary..."
  DRIVERS_TOOLS_PYTHON="$(ensure_python3 2>/dev/null)"
  if [ -z "${DRIVERS_TOOLS_PYTHON}" ]; then
    # For debug purposes
    find_python3
    exit 1
  fi
  echo "Using python $DRIVERS_TOOLS_PYTHON"
  echo "DRIVERS_TOOLS_PYTHON=$DRIVERS_TOOLS_PYTHON" >> $DRIVERS_TOOLS/.env
  echo "Ensuring python binary... done."
fi
export UV_PYTHON=$DRIVERS_TOOLS_PYTHON

# Ensure uv is writing assets to a contained location.
export UV_CACHE_DIR=${DRIVERS_TOOLS}/.local/uv-cache
export UV_TOOL_DIR=${DRIVERS_TOOLS}/.local/uv-tool
export UV_UNMANAGED_INSTALL="1"

if [ "${DOCKER_RUNNING:-}" == "true" ]; then
  _root_dir=$(mktemp -d)
  UV_CACHE_DIR=$_root_dir/uv-cache
  UV_TOOL_DIR=$_root_dir/uv-tool
fi

# If uv is not on path, try see if it is available from the Python toolchain.
if ! command -v uv &>/dev/null; then
  export PATH
  case "${OSTYPE:?}" in
  cygwin)
    PATH="/cygdrive/c/Python/Current/Scripts:${PATH:-}"
    ;;
  darwin*)
    PATH="/Library/Frameworks/Python.Framework/Versions/Current/bin:${PATH:-}"
    ;;
  *)
    PATH="/opt/python/Current/bin:${PATH:-}"
    ;;
  esac
fi

# If there is still no uv, we will install it to $DRIVERS_TOOLS/.bin.
if ! command -V uv &>/dev/null; then
  . ./venv-utils.sh
  _venv_dir="$(mktemp -d)"
  if [ "Windows_NT" = "${OS:-}" ]; then
    _venv_dir="$(cygpath -m $_venv_dir)"
  fi
  echo "Installing uv using pip..."
  venvcreate "$DRIVERS_TOOLS_PYTHON" "$_venv_dir"
  # Install uv into the newly created venv.
  python -m pip install -q --force-reinstall uv
  _suffix=""
  if [ "Windows_NT" = "${OS:-}" ]; then
    _suffix=".exe"
  fi
  # Symlink uv and uvx binaries.
  _install_dir=${DRIVERS_TOOLS}/.bin
  mkdir -p $_install_dir
  ln -s "$(which uv)" $_install_dir/uv${_suffix}
  ln -s "$(which uvx)" $_install_dir/uvx${_suffix}
  echo "Installed to ${_install_dir}"
  deactivate
  echo "Installing uv using pip... done."
fi

# uv should be on the path at this point.
if ! command -V uv &>/dev/null; then
  echo "Could not install uv!"
  exit 1
fi

# Ensure there is a venv available in the script dir for backward compatibility.
uv venv venv &>/dev/null
[[ -d venv ]]

popd >/dev/null
pushd "$TARGET_DIR" >/dev/null

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
  UV_TOOL_BIN_DIR=${TMP_DIR} uv tool install -q ${EXTRA_ARGS} --with certifi --force --editable .
  filenames=$(ls ${TMP_DIR})
  for filename in $filenames; do
    mv $TMP_DIR/$filename "$1/${filename//.exe/}"
  done
  rm -rf $TMP_DIR
else
  UV_TOOL_BIN_DIR=$(pwd) uv tool install -q ${EXTRA_ARGS} --with certifi --force --editable .
fi

popd >/dev/null # "$TARGET_DIR"
