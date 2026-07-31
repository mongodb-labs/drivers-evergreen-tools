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

# _ensure_uv_add_user_base (internal)
#
# Prepend $1's `pip install --user` script directory to PATH, if not already
# there. That directory is version/platform specific (~/.local/bin on Linux,
# ~/Library/Python/X.Y/bin on macOS, %APPDATA%\Python\PythonXY\Scripts on
# Windows), so ask the interpreter rather than assuming.
#
# A no-op if the interpreter cannot report it. Not meant to be called directly.
_ensure_uv_add_user_base() {
  declare user_base
  user_base="$("${1:?}" -m site --user-base 2>/dev/null)" || return 0
  [ -n "$user_base" ] || return 0

  # Both are added together and only one of them exists on any given platform,
  # so either serves as a sentinel for "already added" -- which keeps repeated
  # calls from growing PATH without end.
  case ":${PATH:-}:" in
  *":$user_base/bin:"*) ;;
  *) export PATH="$user_base/bin:$user_base/Scripts:${PATH:-}" ;;
  esac
}

# ensure_uv
#
# Usage:
#   ensure_uv
#
# Return 0 (true) if `uv` is available on PATH, installing it with
# `pip install --user uv` if it was not already present.
# Return a non-zero value (false) otherwise, after printing an actionable
# error message to stderr.
#
# Sets the following environment variables:
#
# - PYENV_VERSION (only when pyenv is installed)
# - PATH (only when uv had to be installed)
# - UV_TOOL_DIR (only when $DRIVERS_TOOLS is set)
# - UV_CACHE_DIR, UV_PYTHON_INSTALL_DIR (additionally require $CI to be set)
#
# This mainly checks PATH and falls back to a plain `pip install --user`.
# The one exception is a fallback to the MongoDB toolchain's python3, needed
# on hosts (e.g. RHEL7) that have no python3 on PATH at all.
#
# On success, also relocates uv's shared state into the checkout; see
# _ensure_uv_scope_paths above for exactly what is scoped and when.
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

  if uv --version >/dev/null 2>&1; then
    _ensure_uv_scope_paths
    return 0
  fi

  local py=""
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

  # An earlier ensure_uv call may have already installed uv into the `--user`
  # script directory. That PATH addition does not outlive the shell it ran in,
  # and on hosts where the directory is not on the default PATH (e.g. RHEL7,
  # where it is /root/.local/bin) every later script would otherwise pay for
  # another pip install. Look there before reinstalling.
  if [ -n "$py" ]; then
    _ensure_uv_add_user_base "$py"
    if uv --version >/dev/null 2>&1; then
      _ensure_uv_scope_paths
      return 0
    fi
  fi

  if [ -n "$py" ]; then
    echo "uv not found on PATH; installing with '$py -m pip install --user uv'..." >&2

    # Some Python builds (e.g. the deadsnakes PPA used in the docker test
    # images) don't ship pip; bootstrap it from the stdlib bundle, which
    # requires no network access.
    "$py" -m pip --version >/dev/null 2>&1 || "$py" -m ensurepip --user >/dev/null 2>&1 || true

    # PIP_BREAK_SYSTEM_PACKAGES bypasses PEP 668's externally-managed-environment
    # guard, which some distros (e.g. Debian/Ubuntu) enable by default. This is
    # safe here: it's a --user install and does not touch system site-packages.
    #
    # Upgrade pip itself first: some hosts ship a pip too old to recognize
    # uv's wheel tags (e.g. PEP 600 manylinux tags require pip 20.3+). This is
    # a fast no-op when pip is already current.
    PIP_BREAK_SYSTEM_PACKAGES=1 "$py" -m pip install --user -q --upgrade pip || true
    PIP_BREAK_SYSTEM_PACKAGES=1 "$py" -m pip install --user -q uv || true

    _ensure_uv_add_user_base "$py"
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
