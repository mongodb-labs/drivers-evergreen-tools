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
# First look everywhere uv may already be: PATH, ~/.local/bin where uv's own
# installer puts it, and the two places an earlier call may have installed it.
# Failing that, install it with `pip install --user`, and failing that into a
# virtual environment under $TMPDIR.
#
# Both install paths are load-bearing because the host fleet is split. Evergreen's
# debian11 images have python3-pip but no python3-venv, so a venv cannot be built
# there. The remote KMS VMs have python3-venv but no python3-pip, and Debian and
# Ubuntu disable `ensurepip` for the system python, so no pip can be bootstrapped
# there.
#
# The one wrinkle is a fallback to the MongoDB toolchain's python3, needed on
# hosts (e.g. RHEL7) that have no python3 on PATH at all.
#
# On success, also relocates uv's shared state; see _ensure_uv_scope_paths above
# for exactly what is scoped and when.
ensure_uv() {
  # Some hosts (e.g. RHEL8 zseries/power8) have pyenv installed, whose shims
  # intercept `python`/`python3`/`uv` and enforce whichever .python-version
  # file they find walking up from the working directory, failing outright if
  # pyenv doesn't already have that exact version installed (some of these
  # hosts already have a working uv installed under pyenv's own configured
  # version). Defer to pyenv's own global version instead of hardcoding e.g.
  # "system", which may not be where uv/python are actually installed on a
  # given host. This repo ships no .python-version, but a parent directory of
  # the checkout may still have one.
  if command -v pyenv >/dev/null 2>&1; then
    declare pyenv_global
    pyenv_global="$(pyenv global 2>/dev/null | head -n1)" || true
    [ -n "$pyenv_global" ] && export PYENV_VERSION="$pyenv_global"
  fi

  # Kept stable rather than mktemp'd so a later ensure_uv call in a fresh shell
  # reuses the venv instead of rebuilding it. Under CI, Evergreen points TMPDIR at
  # a per-task directory, so the venv is recycled with the task and stays out of
  # the failure artifacts, which are packed from $DRIVERS_TOOLS and
  # $PROJECT_DIRECTORY.
  declare venv_dir="${TMPDIR:-/tmp}"
  venv_dir="${venv_dir%/}/drivers-tools-uv-venv"

  declare py=""
  if command -v python3 >/dev/null 2>&1; then
    py=python3
  else
    # Some legacy hosts (e.g. RHEL7) have no python3 on PATH at all, only an
    # ancient Python 2 `python`, which uv does not support. Look for the
    # MongoDB toolchain's python3, which is present on these hosts, before
    # falling back to plain `python`.
    declare toolchain_py
    toolchain_py="$(compgen -G '/opt/mongodbtoolchain/v*/bin/python3' | sort -V | tail -n1)" || true
    if [ -n "$toolchain_py" ] && [ -x "$toolchain_py" ]; then
      py="$toolchain_py"
    elif command -v python >/dev/null 2>&1; then
      py=python
    fi
  fi

  # Everywhere uv may already be, none of it reliably on PATH in a fresh shell:
  # ~/.local/bin is where uv's own installer puts it and is off the default PATH
  # on some hosts (e.g. RHEL7 root shells), while the venv and the `--user` script
  # directory are where an earlier ensure_uv call put it. Checking them together
  # means a later call in a new shell reuses whichever install happened.
  [ -n "${HOME:-}" ] && _ensure_uv_add_path "$HOME/.local/bin"
  _ensure_uv_add_path "$venv_dir/bin"
  _ensure_uv_add_path "$venv_dir/Scripts"
  [ -n "$py" ] && _ensure_uv_add_user_bin "$py"

  if uv --version >/dev/null 2>&1; then
    _ensure_uv_scope_paths
    return 0
  fi

  # Both install paths are needed, because the host fleet is split: Evergreen's
  # debian11 images ship python3-pip but no python3-venv, so `python3 -m venv`
  # fails outright there, while the remote KMS VMs ship python3-venv but no
  # python3-pip, and Debian and Ubuntu disable `ensurepip` for the system python
  # so nothing can bootstrap one. Neither path alone covers both.
  if [ -n "$py" ]; then
    # pip first, being much cheaper than building a venv. Some Python builds
    # (e.g. the deadsnakes PPA in the docker test images) ship no pip at all;
    # bootstrap it from the stdlib bundle, which needs no network access.
    "$py" -m pip --version >/dev/null 2>&1 || "$py" -m ensurepip --user >/dev/null 2>&1 || true

    if "$py" -m pip --version >/dev/null 2>&1; then
      echo "uv not found; installing it with '$py -m pip install --user uv'..." >&2

      # PIP_BREAK_SYSTEM_PACKAGES bypasses PEP 668's externally-managed-environment
      # guard, which Debian and Ubuntu enable by default. Safe here: a --user
      # install does not touch system site-packages.
      #
      # Upgrade pip first, since one predating PEP 600 (e.g. 20.0.2 on Ubuntu
      # 20.04) mis-resolves uv's wheel tags. A fast no-op when already current.
      PIP_BREAK_SYSTEM_PACKAGES=1 "$py" -m pip install --user -q --upgrade pip || true
      PIP_BREAK_SYSTEM_PACKAGES=1 "$py" -m pip install --user -q uv || true

      _ensure_uv_add_user_bin "$py"
    fi

    if ! uv --version >/dev/null 2>&1; then
      echo "uv not found; installing it into a virtual environment at $venv_dir..." >&2

      # --clear so a previously broken venv is replaced. A working one would have
      # been found above, so anything still here is unusable.
      if "$py" -m venv --clear "$venv_dir" >/dev/null 2>&1; then
        # Windows venvs put the interpreter under Scripts, everything else in bin.
        declare venv_py="$venv_dir/bin/python"
        [ -x "$venv_py" ] || venv_py="$venv_dir/Scripts/python.exe"

        # Upgrade pip for the same wheel-tag reason as above. It matters more
        # here: a venv seeds itself with the pip bundled in the system
        # interpreter, which on Ubuntu 20.04 is that same 20.0.2.
        "$venv_py" -m pip install -q --upgrade pip || true
        "$venv_py" -m pip install -q uv || true
      fi
    fi
  fi

  if uv --version >/dev/null 2>&1; then
    _ensure_uv_scope_paths
    return 0
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
