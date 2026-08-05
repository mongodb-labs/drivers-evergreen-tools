#!/usr/bin/env bash
#
# ensure-uv.sh
#
# Usage:
#   . /path/to/ensure-uv.sh
#   ensure_uv || exit 1
#
# This file defines the following utility function:
#   - ensure_uv
# This function may be invoked from any working directory.

if [ -z "$BASH" ]; then
  echo "ensure-uv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# _ensure_uv_scope_paths (internal)
#
# Keeps uv's shared state out of its default home-directory locations
# (~/.cache/uv, ~/.local/share/uv/{tools,python}), which would otherwise be
# contended when Evergreen hosts are reused or share a home directory.
#
# In CI everything goes under the task's temp directory. Evergreen points
# TMPDIR at a per-task directory outside both $DRIVERS_TOOLS and
# $PROJECT_DIRECTORY, so uv's caches are recycled with the task and never end
# up in the uploaded failure artifacts, which are packed from those two trees.
#
# Outside CI only UV_TOOL_DIR is redirected, since `uv tool install --force`
# would otherwise overwrite a developer's globally installed tools (see
# install-cli.sh, which pins its own uv that way). The cache is deliberately
# left shared so local runs do not re-download everything.
#
# A no-op if there is nowhere suitable to point at: this is best-effort
# hygiene, not a correctness requirement, and ensure_uv() is reachable from
# child shells that do not inherit DRIVERS_TOOLS (handle-paths.sh assigns it
# without exporting). Called automatically by ensure_uv() on success; not
# meant to be called directly.
_ensure_uv_scope_paths() {
  if [ -n "${CI:-}" ]; then
    declare _tmp="${TMPDIR:-${TEMP:-${TMP:-}}}"
    if [ -n "$_tmp" ]; then
      # Strip any trailing slash, and match handle-paths.sh in giving uv a
      # native Windows path -- it rejects /cygdrive/c/... style paths.
      _tmp="${_tmp%/}"
      if [ "${OSTYPE:-}" = cygwin ]; then
        _tmp="$(cygpath -m "$_tmp")"
      fi
      export UV_CACHE_DIR="$_tmp/uv-cache"
      export UV_TOOL_DIR="$_tmp/uv-tool"
      export UV_PYTHON_INSTALL_DIR="$_tmp/uv-python"
      return 0
    fi
  fi

  [ -n "${DRIVERS_TOOLS:-}" ] || return 0
  export UV_TOOL_DIR="${DRIVERS_TOOLS}/.local/uv-tool"
}

# _ensure_uv_add_path (internal)
#
# Prepend $1 to PATH unless it is already there, which keeps repeated ensure_uv
# calls from growing PATH without end. Not meant to be called directly.
_ensure_uv_add_path() {
  declare dir="${1:?}"
  case ":${PATH:-}:" in
  *":$dir:"*) ;;
  *) export PATH="$dir:${PATH:-}" ;;
  esac
}

# _ensure_uv_add_user_bin (internal)
#
# Put $1's `pip install --user` script directory on PATH. That directory is
# version and platform specific (~/.local/bin on Linux, ~/Library/Python/X.Y/bin
# on macOS, %APPDATA%\Python\PythonXY\Scripts on Windows), so ask the interpreter
# rather than assuming. Only one of bin/Scripts exists on any given platform, so
# adding both is harmless.
#
# A no-op if the interpreter cannot report it. Not meant to be called directly.
_ensure_uv_add_user_bin() {
  declare base
  base="$("${1:?}" -m site --user-base 2>/dev/null)" || return 0
  [ -n "$base" ] || return 0
  _ensure_uv_add_path "$base/bin"
  _ensure_uv_add_path "$base/Scripts"
}

# _ensure_uv_install (internal)
#
# Install uv using interpreter $1, building a virtual environment at $2 if needed,
# with all output appended to $3. Not meant to be called directly.
#
# Tries `pip install --user` and then a virtual environment, because no single
# method covers every host we run on:
#
# - Remote KMS VMs provisioned before python3-pip was added to their setup scripts
#   have no system pip. These are real Debian 11 cloud images, and Debian disables
#   `ensurepip` for the system python, so only the venv works there.
# - Evergreen's debian11 images have pip but no python3-venv, so `python3 -m venv`
#   fails outright and only pip works there.
# - Callers already inside an active venv have pip, but pip refuses `--user`
#   inside one, so again only the venv works.
# - The docker test images install a deadsnakes python with venv but no pip, so the
#   venv covers them as well.
#
# Every step tolerates failure, since a later one may still succeed.
_ensure_uv_install() {
  declare py="${1:?}" venv_dir="${2:?}" log="${3:?}"

  if "$py" -m pip --version >/dev/null 2>&1; then
    echo "uv not found; installing it with '$py -m pip install --user uv'..." >&2

    # PIP_BREAK_SYSTEM_PACKAGES bypasses PEP 668's externally-managed guard, which
    # Debian and Ubuntu enable. Safe here: `--user` leaves system site-packages
    # alone. Upgrading pip first matters because one predating PEP 600 (20.0.2 on
    # Ubuntu 20.04) mis-resolves uv's wheel tags.
    PIP_BREAK_SYSTEM_PACKAGES=1 "$py" -m pip install --user -q --upgrade pip >>"$log" 2>&1 || true
    PIP_BREAK_SYSTEM_PACKAGES=1 "$py" -m pip install --user -q uv >>"$log" 2>&1 || true

    _ensure_uv_add_user_bin "$py"
  fi

  uv --version >/dev/null 2>&1 && return 0

  echo "uv not found; installing it into a virtual environment at $venv_dir..." >&2

  # --clear replaces a previously broken venv; a working one was found already.
  "$py" -m venv --clear "$venv_dir" >>"$log" 2>&1 || return 0

  # Windows venvs put the interpreter under Scripts, everything else in bin. A
  # venv seeds itself with the system interpreter's pip, so it needs the same
  # upgrade for the same reason.
  declare venv_py="$venv_dir/bin/python"
  [ -x "$venv_py" ] || venv_py="$venv_dir/Scripts/python.exe"
  "$venv_py" -m pip install -q --upgrade pip >>"$log" 2>&1 || true
  "$venv_py" -m pip install -q uv >>"$log" 2>&1 || true
}

# ensure_uv
#
# Usage:
#   ensure_uv
#
# Return 0 (true) if `uv` is available on PATH, installing it if it was not
# already present.
# Return a non-zero value (false) otherwise, after printing an actionable
# error message to stderr.
#
# Sets the following environment variables:
#
# - PYENV_VERSION (only when pyenv is installed)
# - PATH (~/.local/bin, the venv, and pip's `--user` script directory)
# - UV_TOOL_DIR (only when $DRIVERS_TOOLS is set)
# - UV_CACHE_DIR, UV_PYTHON_INSTALL_DIR (additionally require $CI to be set)
#
# Looks everywhere uv may already be, and only then hands off to
# _ensure_uv_install, which documents why installing it takes two attempts.
#
# On success, also relocates uv's shared state; see _ensure_uv_scope_paths.
ensure_uv() {
  # Some hosts (e.g. RHEL8 zseries/power8) have pyenv, whose shims intercept
  # python/uv and enforce whichever .python-version they find walking up from the
  # working directory, failing if pyenv lacks that exact version. Defer to pyenv's
  # own global version rather than hardcoding e.g. "system", which may not be
  # where uv is actually installed.
  if command -v pyenv >/dev/null 2>&1; then
    declare pyenv_global
    pyenv_global="$(pyenv global 2>/dev/null | head -n1)" || true
    [ -n "$pyenv_global" ] && export PYENV_VERSION="$pyenv_global"
  fi

  # Stable rather than mktemp'd, so a later call in a fresh shell reuses the venv.
  # Under CI, Evergreen points TMPDIR at a per-task directory, so it is recycled
  # with the task and stays out of the uploaded failure artifacts.
  declare venv_dir="${TMPDIR:-/tmp}"
  venv_dir="${venv_dir%/}/drivers-tools-uv-venv"

  declare py=""
  if command -v python3 >/dev/null 2>&1; then
    py=python3
  else
    # Some legacy hosts (e.g. RHEL7) have no python3 on PATH at all, only an
    # ancient Python 2 `python` that uv does not support. Prefer the MongoDB
    # toolchain's python3, which those hosts do have.
    declare toolchain_py
    toolchain_py="$(compgen -G '/opt/mongodbtoolchain/v*/bin/python3' | sort -V | tail -n1)" || true
    if [ -n "$toolchain_py" ] && [ -x "$toolchain_py" ]; then
      py="$toolchain_py"
    elif command -v python >/dev/null 2>&1; then
      py=python
    fi
  fi

  # None of these is reliably on PATH in a fresh shell: ~/.local/bin is where uv's
  # own installer puts it, and the others are where an earlier call put it.
  [ -n "${HOME:-}" ] && _ensure_uv_add_path "$HOME/.local/bin"
  _ensure_uv_add_path "$venv_dir/bin"
  _ensure_uv_add_path "$venv_dir/Scripts"
  [ -n "$py" ] && _ensure_uv_add_user_bin "$py"

  if uv --version >/dev/null 2>&1; then
    _ensure_uv_scope_paths
    return 0
  fi

  # Past this point uv is genuinely absent and has to be installed. Output is
  # collected rather than printed, since each attempt is expected to fail on some
  # hosts and only a total failure is worth reporting.
  declare log="${venv_dir}-install.log"
  : >"$log" 2>/dev/null || log=/dev/null

  [ -n "$py" ] && _ensure_uv_install "$py" "$venv_dir" "$log"

  if uv --version >/dev/null 2>&1; then
    _ensure_uv_scope_paths
    return 0
  fi

  # Tail, because pip's connection retries can run to dozens of lines and the
  # message that explains the failure is the last one.
  if [ "$log" != /dev/null ] && [ -s "$log" ]; then
    echo "Last output from the failed install attempts (full log: $log):" >&2
    tail -n 20 "$log" | sed 's/^/  /' >&2
    echo >&2
  fi

  cat <<'EOF' >&2
ERROR: could not find or install `uv`.

Install it manually, then re-run:
  https://docs.astral.sh/uv/getting-started/installation/

If you believe uv/pip should already be available in this environment,
please file a ticket in the DEVPROD Jira project:
  https://jira.mongodb.org/projects/DEVPROD
EOF
  return 1
}
