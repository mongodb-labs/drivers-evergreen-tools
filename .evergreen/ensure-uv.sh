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

# Captured while sourcing, because ensure_uv may be called from any working
# directory and needs to find find-python3.sh beside this file.
_ensure_uv_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# _ensure_uv_supports_uv (internal)
#
# Return 0 (true) if interpreter $1 is new enough for uv, which publishes no
# distribution below Python 3.8. Not meant to be called directly.
_ensure_uv_supports_uv() {
  "${1:?}" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1
}

# _ensure_uv_have_uv (internal)
#
# Return 0 (true) if the uv on PATH is one we can use. uv 0.10.0 stopped
# invalidating the lockfile versions after an exclude-newer change, which
# drivers-tools relies on, so anything older counts as absent and gets replaced
# rather than reused. Not meant to be called directly.
_ensure_uv_have_uv() {
  declare version
  version="$(uv --version 2>/dev/null)" || return 1
  # e.g. "uv 0.12.3 (b88d7c5c4 2026-07-28)" -> "0.12.3"
  version="${version#uv }"
  version="${version%% *}"
  [ -n "$version" ] || return 1
  [ "$(printf '%s\n' 0.10 "$version" | sort -V | head -n1)" = "0.10" ]
}

# _ensure_uv_publish (internal)
#
# Link the uv now on PATH into $DRIVERS_TOOLS/.bin, the directory
# ensure-binary.sh keeps tool binaries in and handle-paths.sh puts on PATH, so a
# later script in a fresh shell finds it without repeating the install. A no-op
# when DRIVERS_TOOLS is unset, which is the case in child shells that do not
# inherit it. Not meant to be called directly.
_ensure_uv_publish() {
  [ -n "${DRIVERS_TOOLS:-}" ] || return 0

  declare src
  src="$(command -v uv 2>/dev/null)" || return 0
  [ -n "$src" ] || return 0

  declare dest="$DRIVERS_TOOLS/.bin"
  [ "$src" = "$dest/uv" ] && return 0
  mkdir -p "$dest" 2>/dev/null || return 0

  # Symlinks need a privilege Windows does not grant by default, so fall back to
  # a copy there. Either way this is best-effort: uv is already on PATH.
  ln -sf "$src" "$dest/uv" 2>/dev/null || cp -f "$src" "$dest/uv" 2>/dev/null || return 0
  _ensure_uv_add_path "$dest"
}

# _ensure_uv_install (internal)
#
# Install uv using interpreter $1, building a virtual environment at $2 if needed,
# with all output appended to $3. Not meant to be called directly.
#
# Tries a virtual environment and then `pip install --user`, because no single
# method covers every host we run on:
#
# - Remote KMS VMs provisioned before python3-pip was added to their setup scripts
#   have no system pip. These are real Debian 11 cloud images, and Debian disables
#   `ensurepip` for the system python, so only the venv works there.
# - Callers already inside an active venv have pip, but pip refuses `--user`
#   inside one, so again only the venv works.
# - The docker test images install a deadsnakes python with venv but no pip, so the
#   venv covers them as well.
# - Evergreen's debian11 images are the one case that runs the other way: they have
#   pip but no python3-venv, so `python3 -m venv` fails outright and pip is the only
#   way through. A venv-only ensure_uv broke exactly those hosts once already; see
#   test_no_venv_module in tests/test-remote-kms-provisioning.sh.
#
# The venv goes first because it is self-contained: it neither depends on nor
# disturbs whatever the host's own python has in its `--user` directory.
#
# Every step tolerates failure, since a later one may still succeed.
_ensure_uv_install() {
  declare py="${1:?}" venv_dir="${2:?}" log="${3:?}"

  echo "uv not found; installing it into a virtual environment at $venv_dir with $py..." >&2

  # --clear replaces a previously broken venv; a working one was found already.
  if "$py" -m venv --clear "$venv_dir" >>"$log" 2>&1; then
    # Windows venvs put the interpreter under Scripts, everything else in bin. A
    # venv seeds itself with the system interpreter's pip, so it needs the same
    # upgrade as below, for the same reason.
    declare venv_py="$venv_dir/bin/python"
    [ -x "$venv_py" ] || venv_py="$venv_dir/Scripts/python.exe"
    "$venv_py" -m pip install -q --upgrade pip >>"$log" 2>&1 || true
    "$venv_py" -m pip install -q uv >>"$log" 2>&1 || true

    _ensure_uv_add_path "$venv_dir/bin"
    _ensure_uv_add_path "$venv_dir/Scripts"
  fi

  _ensure_uv_have_uv && return 0

  "$py" -m pip --version >/dev/null 2>&1 || return 0

  echo "uv not found; installing it with '$py -m pip install --user uv'..." >&2

  # PIP_BREAK_SYSTEM_PACKAGES bypasses PEP 668's externally-managed guard, which
  # Debian and Ubuntu enable. Safe here: `--user` leaves system site-packages
  # alone. Upgrading pip first matters because one predating PEP 600 (20.0.2 on
  # Ubuntu 20.04) mis-resolves uv's wheel tags.
  PIP_BREAK_SYSTEM_PACKAGES=1 "$py" -m pip install --user -q --upgrade pip >>"$log" 2>&1 || true
  PIP_BREAK_SYSTEM_PACKAGES=1 "$py" -m pip install --user -q uv >>"$log" 2>&1 || true

  _ensure_uv_add_user_bin "$py"
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
# - PATH (~/.local/bin, $DRIVERS_TOOLS/.bin, the venv, and pip's `--user` dir)
# - UV_TOOL_DIR (only when $DRIVERS_TOOLS is set)
# - UV_CACHE_DIR, UV_PYTHON_INSTALL_DIR (additionally require $CI to be set)
#
# Looks everywhere uv may already be -- accepting one only if it is recent enough,
# see _ensure_uv_have_uv -- and only then hands off to _ensure_uv_install, which
# documents why installing it takes two attempts.
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

  # find_python3 is drivers-tools' own answer to "which python3 is usable here":
  # it wants 3.9+ with pip and venv, rejects free-threaded and prerelease builds,
  # and prefers the MongoDB toolchain over whatever the distro shipped. That last
  # part is what gets RHEL 8.2 working, where the platform python3 is 3.6 and no
  # amount of retrying can install uv with it.
  declare py=""
  command -v ensure_python3 >/dev/null 2>&1 || . "$_ensure_uv_dir/find-python3.sh"
  py="$(ensure_python3 2>/dev/null)" || py=""

  # find_python3 holds out for 3.9 while uv itself only needs 3.8, so a host
  # whose best interpreter is 3.8 -- Ubuntu 20.04 is the one we still run on --
  # finds nothing above and would otherwise be stranded.
  if [ -z "$py" ]; then
    declare candidate
    for candidate in python3 python; do
      command -v "$candidate" >/dev/null 2>&1 || continue
      if _ensure_uv_supports_uv "$candidate"; then
        py="$candidate"
        break
      fi
    done
  fi

  # Resolved to an absolute path rather than left as a bare name: the venv below
  # goes on PATH ahead of everything, and a venv that fails partway through (see
  # _ensure_uv_install) leaves a pip-less interpreter of the same name sitting in
  # it. A bare `python3` would silently become that one.
  if [ -n "$py" ]; then
    py="$(command -v "$py" 2>/dev/null)" || py=""
  fi

  # None of these is reliably on PATH in a fresh shell. ~/.local/bin is where uv's
  # own installer puts it and is off the default PATH on some hosts (RHEL7 root
  # shells), and the rest are where an earlier ensure_uv call put it. Scripts is the
  # Windows spelling of bin.
  [ -n "${HOME:-}" ] && _ensure_uv_add_path "$HOME/.local/bin"
  [ -n "${DRIVERS_TOOLS:-}" ] && _ensure_uv_add_path "$DRIVERS_TOOLS/.bin"
  _ensure_uv_add_path "$venv_dir/bin"
  _ensure_uv_add_path "$venv_dir/Scripts"
  [ -n "$py" ] && _ensure_uv_add_user_bin "$py"

  if _ensure_uv_have_uv; then
    _ensure_uv_publish
    _ensure_uv_scope_paths
    return 0
  fi

  # Past this point uv is genuinely absent and has to be installed. Output is
  # collected rather than printed, since each attempt is expected to fail on some
  # hosts and only a total failure is worth reporting.
  # Beside the venv, so there is nothing to clean up. Falls back to discarding the
  # output if $TMPDIR is not writable, which is better than failing over a log.
  declare log="${venv_dir}-install.log"
  : >"$log" 2>/dev/null || log=/dev/null

  [ -n "$py" ] && _ensure_uv_install "$py" "$venv_dir" "$log"

  if _ensure_uv_have_uv; then
    _ensure_uv_publish
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
