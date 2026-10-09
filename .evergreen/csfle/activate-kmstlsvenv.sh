#!/usr/bin/env bash
#
# activate-kmstlsvenv.sh
#
# Usage:
#   . ./activate-kmstlsvenv.sh
#
# Creates and/or activates the root workspace .venv with the csfle group
# from the root pyproject.toml. May be invoked from any working directory; on
# error, nothing is left activated and activate_kmstlsvenv returns non-zero.
#
# pip is installed for backwards compatibility with the legacy virtualenv
# workflow; `uv pip` works as well.

if [ -z "$BASH" ]; then
  echo "activate-kmstlsvenv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# Automatically invoked by activate-kmstlsvenv.sh.
activate_kmstlsvenv() {
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

  # Sync the csfle group into the root .venv (idempotent). --inexact keeps
  # other groups' packages (and pip, which is not part of the group), so
  # sourcing another feature's activate script does not uninstall the
  # csfle dependencies.
  #
  # Ensure the toolchain for building cryptography's sdist on arches without
  # prebuilt wheels: a Rust toolchain, and a local OpenSSL 3 build where the
  # system OpenSSL is older than 3.0. No-op where wheels exist; see
  # ensure-build-deps.sh for the arch list.
  # shellcheck source=../ensure-build-deps.sh
  . "$root/.evergreen/ensure-build-deps.sh" || return
  uv sync --project "$root" --group csfle --inexact || return
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

activate_kmstlsvenv
