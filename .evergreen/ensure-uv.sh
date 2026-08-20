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

# _ensure_uv_publish (internal)
#
# Link the uv now on PATH into $DRIVERS_TOOLS/.bin, where ensure-binary.sh keeps
# tool binaries and handle-paths.sh looks, so a later script in a fresh shell
# skips the install. A no-op when DRIVERS_TOOLS is unset, as it is in child
# shells that do not inherit it. Not meant to be called directly.
_ensure_uv_publish() {
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
# and appending all output to $3. Not meant to be called directly.
#
# `pip install --user` is the method. Every host we control has pip: the docker
# test images install it, Evergreen hosts get it with the toolchain python, and
# the KMS VM setup scripts have installed python3-pip since PYTHON-5985.
#
# Two shapes need something else:
#
# - A caller already inside an active venv, which is how the Node OIDC tests
#   invoke this. pip refuses `--user` there, and the venv is the right target
#   anyway, so install into it. Only reachable without a toolchain, since an
#   interpreter outside the venv is unaffected by it.
# - A KMS VM provisioned before PYTHON-5985, which has no pip at all. Debian
#   refuses `ensurepip` outside a venv, so a venv is the only route left. Release
#   branches still pin drivers-tools from before that change, so this is legacy
#   support rather than a live path; see test_legacy_vm_without_pip in
#   tests/test-remote-kms-provisioning.sh.
#
#   DRIVERS-XXXX (placeholder, not yet filed) tracks getting those pins past
#   PYTHON-5985. Delete this branch when it closes.
#
# Every step tolerates failure; the caller reports whether uv ended up on PATH.
_ensure_uv_install() {
  declare py="${1:?}" venv_dir="${2:?}" log="${3:?}"

  if "$py" -m pip --version >>"$log" 2>&1; then
    if "$py" -c 'import sys; sys.exit(0 if sys.prefix != sys.base_prefix else 1)'; then
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

  # None of these is reliably on PATH in a fresh shell. ~/.local/bin is where uv's
  # own installer puts it and is off the default PATH on some hosts (RHEL7 root
  # shells), and the rest are where an earlier ensure_uv call put it. Scripts is the
  # Windows spelling of bin. None of them needs an interpreter to name, so this is
  # the cheap half of the search and it runs first.
  [ -n "${HOME:-}" ] && _ensure_uv_add_path "$HOME/.local/bin"
  [ -n "${DRIVERS_TOOLS:-}" ] && _ensure_uv_add_path "$DRIVERS_TOOLS/.bin"
  _ensure_uv_add_path "$venv_dir/bin"
  _ensure_uv_add_path "$venv_dir/Scripts"

  if uv --version >/dev/null 2>&1; then
    _ensure_uv_publish
    _ensure_uv_scope_paths
    return 0
  fi

  # Only now is an interpreter worth looking for. $DRIVERS_TOOLS_PYTHON wins if
  # the caller set it, the same contract find-python3.sh offers and setup.sh
  # writes into .env. Otherwise the MongoDB toolchain, because it is the one we
  # control: it rescues hosts whose system python3 is absent, as on RHEL 7, or too
  # old for uv, as on RHEL 8.2 where the platform python3 is 3.6 and uv publishes
  # no distribution for it.
  #
  # Resolved to an absolute path, so that a venv arriving on PATH later cannot
  # re-point a bare name at a different interpreter.
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

  # pip's `--user` script directory is version and platform specific, so naming it
  # takes the interpreter we just found. On Linux it is the ~/.local/bin already
  # added above; on macOS and Windows it is not, so an earlier --user install is
  # only reachable from here.
  [ -n "$py" ] && _ensure_uv_add_user_bin "$py"

  if uv --version >/dev/null 2>&1; then
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

  if uv --version >/dev/null 2>&1; then
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
