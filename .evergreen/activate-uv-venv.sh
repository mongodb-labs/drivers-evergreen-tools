#!/usr/bin/env bash
#
# activate-uv-venv.sh
#
# Usage:
#   . /path/to/activate-uv-venv.sh
#   activate_uv_venv group [--cryptography-build]
#
# Defines activate_uv_venv, which creates and/or activates the root uv
# workspace's .venv from the named dependency group in the root
# pyproject.toml, leaving `python` pointing at that environment. May be
# invoked from any working directory. On error, nothing is left activated
# and activate_uv_venv returns non-zero.
#
# Pass --cryptography-build for groups that need cryptography. On s390x,
# cryptography publishes no wheels, so the sdist build toolchain must be
# ensured before uv sync.
#
# pip is installed for backwards compatibility with the legacy virtualenv
# workflow; `uv pip` works as well.
#
# The activate-<feature>venv.sh scripts in the feature directories are thin
# wrappers around this helper.

if [ -z "$BASH" ]; then
  echo "activate-uv-venv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

activate_uv_venv() {
  if [ -z "${1:-}" ]; then
    echo "activate_uv_venv: a dependency group name is required" 1>&2
    return 1
  fi
  local -r group="$1"
  local cryptography_build=""
  if [ -n "${2:-}" ]; then
    if [ "$2" = "--cryptography-build" ]; then
      cryptography_build=1
    else
      echo "activate_uv_venv: unknown option '$2'" 1>&2
      return 1
    fi
  fi

  # Repo root, relative to this script. uv needs a native Windows path on
  # Cygwin (it rejects /cygdrive/... paths).
  local root
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || return 1
  if [ "${OSTYPE:-}" = cygwin ]; then
    root="$(cygpath -m "$root")"
  fi

  # Ensure uv is available.
  # shellcheck source=.evergreen/ensure-uv.sh
  . "$root/.evergreen/ensure-uv.sh" || return
  ensure_uv || return

  if [ -n "$cryptography_build" ]; then
    # shellcheck source=.evergreen/ensure-cryptography-build.sh
    . "$root/.evergreen/ensure-cryptography-build.sh" || return
  fi

  # Sync the group into the root .venv (idempotent). --inexact keeps other
  # groups' packages (and pip, which is not part of any group), so sourcing
  # another feature's activate script does not uninstall these dependencies.
  uv sync --project "$root" --group "$group" --inexact || return
  # Restore pip, which uv does not seed into managed venvs.
  uv pip install --python "$root/.venv" --quiet pip || return

  # Activate the environment (Scripts/ instead of bin/ on Windows).
  if [ -f "$root/.venv/bin/activate" ]; then
    # shellcheck source=/dev/null
    . "$root/.venv/bin/activate"
  elif [ -f "$root/.venv/Scripts/activate" ]; then
    # shellcheck source=/dev/null
    . "$root/.venv/Scripts/activate"
  else
    echo "Could not find the activate script in $root/.venv!" 1>&2
    return 1
  fi
}
