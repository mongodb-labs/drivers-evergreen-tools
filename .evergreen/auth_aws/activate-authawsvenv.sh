#!/usr/bin/env bash
#
# activate-authawsvenv.sh
#
# Usage:
#   . ./activate-authawsvenv.sh
#
# Creates and/or activates the Python environment for the auth_aws test
# scripts, leaving `python` pointing at an environment with the auth_aws
# dependencies (pymongo[aws], boto3, pyop). The environment is the root uv
# workspace's .venv, built from the auth_aws group in the root pyproject.toml.
# May be invoked from any working directory. On error, nothing is left
# activated and activate_authawsvenv returns non-zero.

if [ -z "$BASH" ]; then
  echo "activate-authawsvenv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# Automatically invoked by activate-authawsvenv.sh.
activate_authawsvenv() {
  # Repo root, relative to this script. uv needs a native Windows path on
  # Cygwin (it rejects /cygdrive/... paths).
  local root
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) || return 1
  if [ "${OSTYPE:-}" = cygwin ]; then
    root="$(cygpath -m "$root")"
  fi

  # Ensure uv is available.
  # shellcheck source=.evergreen/ensure-uv.sh
  . "$root/.evergreen/ensure-uv.sh" || return
  ensure_uv || return

  # Sync the auth_aws group into the root .venv (idempotent).
  uv sync --project "$root" --group auth_aws || return

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

activate_authawsvenv
