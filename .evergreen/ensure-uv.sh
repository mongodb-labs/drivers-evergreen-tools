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
# Put a working uv on PATH, installing one if there is none. Returns non-zero and
# says why if it cannot. Safe to call repeatedly.
ensure_uv() {
  # pyenv shims enforce whichever .python-version they find above the working
  # directory: on the RHEL 8 zseries and power8 hosts, a .python-version file
  # naming a version pyenv lacks makes even `uv --version` fail. Defer to its
  # global version instead.
  if command -v pyenv >/dev/null 2>&1; then
    declare pyenv_global
    pyenv_global="$(pyenv global 2>/dev/null | head -n1)" || true
    [ -n "$pyenv_global" ] && export PYENV_VERSION="$pyenv_global"
  fi

  # Stable rather than mktemp'd, so a later call in a fresh shell reuses the venv.
  declare venv_dir="${TMPDIR:-/tmp}"
  venv_dir="${venv_dir%/}/drivers-tools-uv-venv"

  # The cheap half of the search, needing no interpreter to name: where uv's own
  # installer or an earlier call put it. Windows uses a Scripts directory
  # instead of bin.
  [ -n "${HOME:-}" ] && _ensure_uv_add_path "$HOME/.local/bin"
  [ -n "${DRIVERS_TOOLS:-}" ] && _ensure_uv_add_path "$DRIVERS_TOOLS/.bin"
  _ensure_uv_add_path "$venv_dir/bin"
  _ensure_uv_add_path "$venv_dir/Scripts"

  if uv --version >/dev/null 2>&1; then
    _ensure_uv_link_into_bin
    _ensure_uv_scope_paths
    return 0
  fi

  # Only now is an interpreter worth finding. $DRIVERS_TOOLS_PYTHON wins, the same
  # contract find-python3.sh offers, then the toolchain, which rescues hosts whose
  # python3 is missing (RHEL 7) or too old for uv (RHEL 8.2 arm ships 3.6). Absolute,
  # so a venv arriving on PATH later cannot re-point a bare name.
  declare py="" candidate resolved
  for candidate in \
    "${DRIVERS_TOOLS_PYTHON:-}" \
    $(compgen -G '/opt/mongodbtoolchain/v*/bin/python3' | sort -Vr) \
    python3 \
    python; do
    [ -n "$candidate" ] || continue
    resolved="$(command -v "$candidate" 2>/dev/null)" || continue
    [ -n "$resolved" ] || continue
    py="$resolved"
    break
  done

  # Naming pip's --user directory takes the interpreter, and on macOS and Windows
  # it is not the ~/.local/bin added above.
  [ -n "$py" ] && _ensure_uv_add_user_bin "$py"

  if uv --version >/dev/null 2>&1; then
    _ensure_uv_link_into_bin
    _ensure_uv_scope_paths
    return 0
  fi

  # Collected rather than printed: an attempt is expected to fail on some hosts,
  # and only a total failure is worth reporting. Discarded if $TMPDIR is read-only.
  declare log="${venv_dir}-install.log"
  : >"$log" 2>/dev/null || log=/dev/null

  [ -n "$py" ] && _ensure_uv_install "$py" "$venv_dir" "$log"

  if uv --version >/dev/null 2>&1; then
    _ensure_uv_link_into_bin
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

# _ensure_uv_scope_paths (internal)
#
# Move uv's cache and tool directories out of the home directory, which Evergreen
# hosts contend over when they share one. Under CI that is $TMPDIR, recycled with
# the task; elsewhere only UV_TOOL_DIR moves, since `uv tool install --force`
# would otherwise overwrite a developer's own tools.
#
# Best-effort, and a no-op when there is nowhere to point at. Not meant to be
# called directly.
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

# _ensure_uv_link_into_bin (internal)
#
# Link the uv now on PATH into $DRIVERS_TOOLS/.bin, where ensure-binary.sh keeps
# tool binaries and handle-paths.sh looks, so a later script in a fresh shell
# skips the install. A no-op when DRIVERS_TOOLS is unset, as it is in child
# shells that do not inherit it. Not meant to be called directly.
_ensure_uv_link_into_bin() {
  [ -n "${DRIVERS_TOOLS:-}" ] || return 0

  declare src
  src="$(command -v uv 2>/dev/null)" || return 0

  declare dest="$DRIVERS_TOOLS/.bin"
  [ "$src" = "$dest/uv" ] && return 0
  mkdir -p "$dest" 2>/dev/null || return 0

  # Windows does not grant symlink privilege by default. Best-effort either way,
  # since uv is already on PATH.
  ln -sf "$src" "$dest/uv" 2>/dev/null || cp -f "$src" "$dest/uv" 2>/dev/null || return 0
  _ensure_uv_add_path "$dest"
}

# _ensure_uv_install (internal)
#
# Install uv with interpreter $1, using $2 for the virtual environment fallback
# and appending all output to $3. Every step tolerates failure; the caller reports
# whether uv ended up on PATH. Not meant to be called directly.
_ensure_uv_install() {
  declare py="${1:?}" venv_dir="${2:?}" log="${3:?}"

  if "$py" -m pip --version >>"$log" 2>&1; then
    if "$py" -c 'import sys; sys.exit(0 if sys.prefix != sys.base_prefix else 1)'; then
      # pip refuses --user inside an active venv, and the venv is the right
      # target anyway. This is how the Node OIDC tests call ensure_uv.
      echo "uv not found; installing it with '$py -m pip install uv' into the active venv..." >&2
      "$py" -m pip install -q uv >>"$log" 2>&1 || true
    else
      echo "uv not found; installing it with '$py -m pip install --user uv'..." >&2
      # PIP_BREAK_SYSTEM_PACKAGES bypasses PEP 668's externally-managed guard,
      # which Debian and Ubuntu enable. Safe here: `--user` leaves system
      # site-packages alone.
      PIP_BREAK_SYSTEM_PACKAGES=1 "$py" -m pip install --user -q uv >>"$log" 2>&1 || true
    fi
    _ensure_uv_add_user_bin "$py"
    return 0
  fi

  # No pip at all, which now means only a KMS VM provisioned before PYTHON-5985.
  # Debian refuses ensurepip outside a venv, so a venv is the only route left.
  # DRIVERS-XXXX (placeholder, not yet filed) retires this once no branch pins
  # that far back; the kms-legacy variant is what still covers it.
  echo "uv not found and $py has no pip; building a virtual environment at $venv_dir..." >&2

  # --clear replaces a previously broken venv; a working one was found already.
  if "$py" -m venv --clear "$venv_dir" >>"$log" 2>&1; then
    # Windows venvs put the interpreter under Scripts, everything else in bin.
    declare venv_py="$venv_dir/bin/python"
    [ -x "$venv_py" ] || venv_py="$venv_dir/Scripts/python.exe"
    "$venv_py" -m pip install -q uv >>"$log" 2>&1 || true

    _ensure_uv_add_path "$venv_dir/bin"
    _ensure_uv_add_path "$venv_dir/Scripts"
  fi
}
