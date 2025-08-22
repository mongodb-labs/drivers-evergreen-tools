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
  echo "DRIVERS_TOOLS_PYTHON=$DRIVERS_TOOLS_PYTHON" >>$DRIVERS_TOOLS/.env
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
  declare python_path
  case "${OSTYPE:?}" in
  cygwin)
    python_path="/cygdrive/c/Python/Current/Scripts"
    ;;
  darwin*)
    python_path="/Library/Frameworks/Python.Framework/Versions/Current/bin"
    ;;
  *)
    python_path="/opt/python/Current/bin"
    ;;
  esac
  [[ "${PATH:-}" =~ (^|:)"${python_path:?}"(:|$) ]] || PATH="${python_path:?}:${PATH:-}"
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
  # Symlink uv and uvx binaries.
  _install_dir="${DRIVERS_TOOLS}/.bin"
  mkdir -p "$_install_dir"
  if [ "Windows_NT" = "${OS:-}" ]; then
    ln -s "${_venv_dir}/Scripts/uv.exe" "$_install_dir/uv.exe"
    ln -s "${_venv_dir}/Scripts/uvx.exe" "$_install_dir/uvx.exe"
  else
    ln -s "$(which uv)" "$_install_dir/uv"
    ln -s "$(which uvx)" "$_install_dir/uvx"
  fi
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

popd >/dev/null # $SCRIPT_DIR
pushd "$TARGET_DIR" >/dev/null

# uv requires UV_TOOL_BIN_DIR is `C:\a\b\c` instead of `/cygdrive/c/a/b/c` on Windows.
if [[ "${OSTYPE:?}" == cygwin ]]; then
  UV_TOOL_BIN_DIR="$(cygpath -aw .)"
else
  UV_TOOL_BIN_DIR="$(pwd)"
fi
export UV_TOOL_BIN_DIR

# Pin the uv binary version used by subsequent commands.
uv tool install -q --force "uv~=0.8.0"
[[ "${PATH:-}" =~ (^|:)"${UV_TOOL_BIN_DIR:?}"(:|$) ]] || PATH="${UV_TOOL_BIN_DIR:?}:${PATH:-}"
command -V uv
uv --version

# Workaround for https://github.com/astral-sh/uv/issues/5815.
uv export --quiet --frozen --format requirements.txt -o uv-requirements.txt

# Support overriding lockfile dependencies.
if [[ ! -f "${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:-}" ]]; then
  printf "" >|"${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:="uv-override-dependencies.txt"}"
fi

declare uv_install_args
uv_install_args=(
  --quiet
  --force
  --editable
  --with-requirements uv-requirements.txt
  --overrides "${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:?}"
)
uv tool install "${uv_install_args[@]:?}" .

# Support running tool executables on Windows without including the ".exe" suffix.
find . -maxdepth 1 -type f -name '*.exe' -exec \
  bash -c "ln -sf \"\$0\" \"\$(echo \"\$0\" | sed -E -e 's|(.*)\.exe|\1|')\"" {} \;

popd >/dev/null # "$TARGET_DIR"
