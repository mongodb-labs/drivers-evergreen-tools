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
  # s390x (zSeries) hosts have no cryptography wheels: uv builds the sdist,
  # which requires a Rust toolchain (install-rust.sh exports RUSTUP_HOME,
  # CARGO_HOME, and PATH) and OpenSSL 3 headers (install-openssl3.sh builds
  # OpenSSL 3 and exports OPENSSL_DIR and LD_LIBRARY_PATH, since the system
  # OpenSSL 1.1.1 is too old for cryptography 47.0+).
  if [ "$(uname -m)" = "s390x" ]; then
    local _shopts="$-"
    # shellcheck source=../install-rust.sh
    . "$root/.evergreen/install-rust.sh" || return
    # shellcheck source=../install-openssl3.sh
    . "$root/.evergreen/install-openssl3.sh" || return
    # install-rust.sh enables `set -eu`; restore the caller's shell options.
    [[ "$_shopts" == *e* ]] || set +e
    [[ "$_shopts" == *u* ]] || set +u
  fi
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
