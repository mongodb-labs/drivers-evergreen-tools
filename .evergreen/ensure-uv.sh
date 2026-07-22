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
# This mainly checks PATH and falls back to a plain `pip install --user`.
# The one exception is a fallback to the MongoDB toolchain's python3, needed
# on hosts (e.g. RHEL7) that have no python3 on PATH at all.
ensure_uv() {
  # Some hosts (e.g. RHEL8 zseries/power8) have pyenv installed, whose shims
  # intercept `python`/`python3`/`uv` and enforce the repo's .python-version
  # file, failing outright if pyenv doesn't already have that exact version
  # installed (some of these hosts already have a working uv installed under
  # pyenv's own configured version). Defer to pyenv's own global version
  # rather than the repo's file, instead of hardcoding e.g. "system", which
  # may not be where uv/python are actually installed on a given host.
  if command -v pyenv >/dev/null 2>&1; then
    declare pyenv_global
    pyenv_global="$(pyenv global 2>/dev/null | head -n1)"
    [ -n "$pyenv_global" ] && export PYENV_VERSION="$pyenv_global"
  fi

  if uv --version >/dev/null 2>&1; then
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
    toolchain_py="$(ls -d /opt/mongodbtoolchain/v*/bin/python3 2>/dev/null | sort -V | tail -n1)"
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

    if ! uv --version >/dev/null 2>&1; then
      # Some hosts ship a pip too old to recognize uv's wheel tags (e.g. PEP
      # 600 manylinux tags require pip 20.3+). Upgrade pip itself and retry.
      echo "uv still not found; upgrading pip and retrying..." >&2
      PIP_BREAK_SYSTEM_PACKAGES=1 "$py" -m pip install --user -q --upgrade pip || true
      PIP_BREAK_SYSTEM_PACKAGES=1 "$py" -m pip install --user -q uv || true
    fi
  fi

  if uv --version >/dev/null 2>&1; then
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
