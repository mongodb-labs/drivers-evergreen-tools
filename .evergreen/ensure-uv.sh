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
# Confines uv's shared state to the Evergreen checkout (under
# $DRIVERS_TOOLS/.local) instead of uv's default shared home-directory
# locations (~/.cache/uv, ~/.local/share/uv/{tools,python}), avoiding
# cross-task/cross-host contention when Evergreen hosts are reused or share a
# home directory.
#
# UV_TOOL_DIR is always scoped: `uv tool install --force` would otherwise
# overwrite a developer's globally installed tools (see install-cli.sh, which
# pins its own uv that way). The cache and managed interpreters are only
# scoped in CI (i.e. when $CI is set), so local runs keep uv's shared cache
# rather than re-downloading everything on every invocation.
#
# A no-op when $DRIVERS_TOOLS is unset: this is best-effort hygiene, not a
# correctness requirement, and ensure_uv() is reachable from child shells that
# do not inherit it (handle-paths.sh assigns DRIVERS_TOOLS without exporting
# it). Called automatically by ensure_uv() on success; not meant to be called
# directly.
_ensure_uv_scope_paths() {
  [ -n "${DRIVERS_TOOLS:-}" ] || return 0
  export UV_TOOL_DIR="${DRIVERS_TOOLS}/.local/uv-tool"
  [ -n "${CI:-}" ] || return 0
  export UV_CACHE_DIR="${DRIVERS_TOOLS}/.local/uv-cache"
  export UV_PYTHON_INSTALL_DIR="${DRIVERS_TOOLS}/.local/uv-python"
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
    toolchain_py="$(compgen -G '/opt/mongodbtoolchain/v*/bin/python3' | sort -V | tail -n1)"
    if [ -n "$toolchain_py" ] && [ -x "$toolchain_py" ]; then
      py="$toolchain_py"
    elif command -v python >/dev/null 2>&1; then
      py=python
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

    # `--user` installs console scripts into a version/platform-specific
    # directory (e.g. ~/.local/bin on Linux, ~/Library/Python/X.Y/bin on
    # macOS, %APPDATA%\Python\PythonXY\Scripts on Windows); ask the
    # interpreter where that is rather than assuming.
    declare user_base
    user_base="$("$py" -m site --user-base 2>/dev/null)" || user_base=""
    if [ -n "$user_base" ]; then
      export PATH="$user_base/bin:$user_base/Scripts:$PATH"
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
