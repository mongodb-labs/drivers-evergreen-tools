#!/usr/bin/env bash
# Install the drivers orchestration scripts.

set -eu

if [ -z "$BASH" ]; then
  echo "install-cli.sh must be run in a Bash shell!" 1>&2
  return 1
fi

TARGET_DIR="${1:?"must give a target directory!"}"

# Make it absolute up front, so the pushd calls below cannot invalidate a
# caller-provided relative path. uv rejects /cygdrive/... style paths.
if [[ "${OSTYPE:-}" == cygwin ]]; then
  TARGET_DIR="$(cygpath -m "$(cd "$TARGET_DIR" && pwd)")"
else
  TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
fi

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

pushd $SCRIPT_DIR >/dev/null

# Ensure uv is available.
. ./ensure-uv.sh
ensure_uv || exit 1

export UV_UNMANAGED_INSTALL="1"

# Point uv at a fresh temp dir in the Docker case, overriding anything
# ensure_uv may have scoped to the checkout.
if [ "${DOCKER_RUNNING:-}" == "true" ]; then
  _root_dir=$(mktemp -d)
  export UV_CACHE_DIR=$_root_dir/uv-cache
  export UV_TOOL_DIR=$_root_dir/uv-tool
  export UV_PYTHON_INSTALL_DIR=$_root_dir/uv-python
fi

# Ensure there is a venv available in the script dir for backward compatibility.
if [ ! -d venv ]; then
  uv venv -p "${DRIVERS_TOOLS_PYTHON:-python}" venv &>/dev/null || uv venv venv
fi
[[ -d venv ]]

popd >/dev/null # $SCRIPT_DIR

# uv resolves the export's lock-relative paths against the cwd, and does not
# discover the workspace from below a parent pyproject.toml, so run from the
# checkout root. TARGET_DIR is already a native Windows path for Cygwin.
UV_TOOL_BIN_DIR="$TARGET_DIR"
export UV_TOOL_BIN_DIR

_workspace_root="$(cd "$SCRIPT_DIR/.." && pwd)"

pushd "$_workspace_root" >/dev/null

pkg_name=$(sed -n -E 's/^name[[:space:]]*=[[:space:]]*"([^"]*)".*$/\1/p' "$TARGET_DIR/pyproject.toml" | head -n1)
if [[ -z "${pkg_name:-}" ]]; then
  echo "No project name found in ${TARGET_DIR}/pyproject.toml!" 1>&2
  exit 1
fi

# Keep in sync with the uv Dependabot uses to regenerate uv.lock
# (https://github.com/dependabot/dependabot-core/blob/main/uv/Dockerfile);
# this floats to the latest 0.12.x, so only Dependabot minor bumps matter.
uv tool install -q --force "uv~=0.12.0"
[[ "${PATH:-}" =~ (^|:)"${UV_TOOL_BIN_DIR:?}"(:|$) ]] || PATH="${UV_TOOL_BIN_DIR:?}:${PATH:-}"
command -V uv
uv --version

# Workaround for https://github.com/astral-sh/uv/issues/5815: uv tool install
# ignores uv.lock, so feed it the locked pins via --with-requirements below.
uv export --quiet --frozen --package "$pkg_name" --format requirements.txt -o "$TARGET_DIR/uv-requirements.txt"

# Support overriding lockfile dependencies.
if [[ ! -f "${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:-}" ]]; then
  printf "" >|"${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:="$TARGET_DIR/uv-override-dependencies.txt"}"
fi

declare uv_install_args
uv_install_args=(
  --quiet
  --force
  --editable
  --with-requirements "$TARGET_DIR/uv-requirements.txt"
  --overrides "${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:?}"
)
uv tool install "${uv_install_args[@]:?}" "$TARGET_DIR"

popd >/dev/null # $_workspace_root

# Support running tool executables on Windows without including the ".exe" suffix.
(
  cd "$TARGET_DIR"
  for name_exe in *.exe; do
    # Skip files which do not exist or are not executable.
    [[ -x "${name_exe:?}" ]] || continue
    # Strip ".exe" at end of filename.
    name="${name_exe%".exe"}"
    # Only create a symlink if the symlink doesn't already exist.
    [[ -x "${name:?}" ]] || ln -sf "${name_exe:?}" "${name:?}"
  done
)
