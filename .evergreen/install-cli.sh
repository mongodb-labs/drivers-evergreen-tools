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

# Ensure uv is available.
. ./ensure-uv.sh
ensure_uv || exit 1

# Ensure uv is writing assets to a contained location.
export UV_CACHE_DIR=${DRIVERS_TOOLS}/.local/uv-cache
export UV_TOOL_DIR=${DRIVERS_TOOLS}/.local/uv-tool
export UV_UNMANAGED_INSTALL="1"

if [ "${DOCKER_RUNNING:-}" == "true" ]; then
  _root_dir=$(mktemp -d)
  UV_CACHE_DIR=$_root_dir/uv-cache
  UV_TOOL_DIR=$_root_dir/uv-tool
fi

# Ensure there is a venv available in the script dir for backward compatibility.
if [ ! -d venv ]; then
  uv venv venv &>/dev/null || uv venv venv
fi
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
(
  for name_exe in *.exe; do
    # Skip files which do not exist or are not executable.
    [[ -x "${name_exe:?}" ]] || continue
    # Strip ".exe" at end of filename.
    name="${name_exe%".exe"}"
    # Only create a symlink if the symlink doesn't already exist.
    [[ -x "${name:?}" ]] || ln -sf "${name_exe:?}" "${name:?}"
  done
)

popd >/dev/null # "$TARGET_DIR"
