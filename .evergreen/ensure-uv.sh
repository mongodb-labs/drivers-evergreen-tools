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

# Absolute workspace root, resolved once at source time: BASH_SOURCE is
# relative to the sourcing shell's working directory, and ensure_uv may later
# run from any directory.
_ensure_uv_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

# _ensure_uv_min_python (internal)
#
# Print the workspace's minimum supported CPython version (e.g. "3.11") from
# requires-python in the root pyproject.toml. Prints nothing and fails if it
# cannot be determined, so callers fall back to uv's interpreter handling.
_ensure_uv_min_python() {
  declare root="${_ensure_uv_root:-}"
  [ -n "$root" ] || return 1
  # awk-scoped so another table's requires-python key cannot match (the same
  # pattern install-cli.sh uses to read the [project] name).
  awk '
    /^[[:space:]]*\[/ {
      in_project = ($0 ~ /^\[[[:space:]]*project[[:space:]]*\][[:space:]]*$/)
    }
    in_project && $0 ~ /^[[:space:]]*requires-python[[:space:]]*=/ {
      if (match($0, /[0-9]+\.[0-9]+/)) {
        print substr($0, RSTART, RLENGTH)
        exit
      }
    }
  ' "$root/pyproject.toml" 2>/dev/null
}

# _ensure_uv_meets_floor (internal)
#
# Succeed if interpreter $1 is a final CPython release of at least $2.$3
# (the workspace floor). Pre-release interpreters never qualify, so a
# toolchain shipping one is not selected for reuse, and neither do other
# implementations: PyPy satisfies the version probe but the workspace
# supports only CPython. Prints nothing.
_ensure_uv_meets_floor() {
  declare py="${1:?}" major="${2:?}" minor="${3:?}"
  "$py" -c "import sys; sys.exit(0 if sys.implementation.name == 'cpython' and sys.version_info >= ($major, $minor) and sys.version_info.releaselevel == 'final' else 1)" >/dev/null 2>&1
}

# _ensure_uv_floor_bootstrap (internal)
#
# Make later uv invocations reuse a host interpreter that satisfies the
# workspace floor, and bootstrap a uv-managed interpreter only when none
# qualifies. Called on both of ensure_uv's success paths. A no-op when no
# floor was parsed (empty $1).
_ensure_uv_floor_bootstrap() {
  declare major="${1:-}" minor="${2:-}" floor_py="${3:-}"
  [ -n "$major" ] || return 0

  if [ -n "$floor_py" ]; then
    # Pin uv to the qualifying interpreter: discovery can settle below the
    # floor (tool installs included), and a PATH entry would shadow an
    # active venv. A pre-set UV_PYTHON wins.
    if [ "${OSTYPE:-}" = cygwin ]; then
      # uv wants native Windows paths; see _ensure_uv_scope_paths.
      floor_py="$(cygpath -m "$floor_py")"
    fi
    export UV_PYTHON="${UV_PYTHON:-$floor_py}"
    return 0
  fi

  # No host interpreter qualifies, so install a uv-managed one and leave uv
  # at its default managed preference. Preferring system here would steer uv
  # back to the undersized host interpreter.
  echo "No host interpreter satisfies the workspace floor (CPython >= $major.$minor). Installing a uv-managed interpreter..." >&2
  uv python install "$major.$minor" || true
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
# version and platform specific, so ask the interpreter's sysconfig for the
# user scheme rather than deriving it from --user-base: on Windows it is
# %APPDATA%\Python\PythonXY\Scripts, not $base/Scripts.
#
# A no-op if the interpreter cannot report it. Not meant to be called directly.
_ensure_uv_add_user_bin() {
  declare base
  # A native Windows interpreter ends its stdout lines with \r\n; a trailing
  # \r would corrupt the PATH entry and break bash's lookup of the directory.
  base="$("${1:?}" -c 'import os, sysconfig; print(sysconfig.get_path("scripts", "nt_user" if os.name == "nt" else "posix_user"))' 2>/dev/null | tr -d '\r')" || return 0
  [ -n "$base" ] || return 0
  if [ "${OSTYPE:-}" = cygwin ]; then
    base="$(cygpath -m "$base")"
  fi
  _ensure_uv_add_path "$base"
}

# _ensure_uv_install (internal)
#
# Install uv using interpreter $1, building a virtual environment at $2 if needed,
# with all output appended to $3. Not meant to be called directly.
#
# Install uv into the active environment when possible; otherwise use
# `pip install --user`, falling back to a throwaway virtual environment, because
# no single method covers every host we run on:
#
# - Callers inside an active venv have pip, but pip refuses `--user` there, so
#   uv installs into that venv and PATH points at it directly.
# - Callers not in a venv install with `pip install --user`, which leaves the
#   system Python's site-packages alone.
# - Remote KMS VMs provisioned before python3-pip was added to their setup scripts
#   have no system pip. These are real Debian 11 cloud images, and Debian disables
#   `ensurepip` for the system python, so only the venv works there.
# - Evergreen's debian11 images have pip but no python3-venv, so `python3 -m venv`
#   fails outright and only pip works there.
#
# Keep the venv fallback. The legacy KMS VMs still need it, and it is the
# backstop for any host where the pip path cannot install uv.
#
# Every step tolerates failure, since a later one may still succeed.
_ensure_uv_install() {
  declare py="${1:?}" venv_dir="${2:?}" log="${3:?}"

  if "$py" -m pip --version >/dev/null 2>&1; then
    if "$py" -c 'import sys; sys.exit(0 if sys.prefix != sys.base_prefix else 1)'; then
      # Callers inside an active venv (e.g. the Node OIDC tests) have pip, but
      # pip refuses `--user` there, so uv goes into the venv instead.
      echo "uv not found; installing it with '$py -m pip install uv' into the venv..." >&2
      "$py" -m pip install -q --upgrade pip >>"$log" 2>&1 || true
      "$py" -m pip install -q uv >>"$log" 2>&1 || true
      # The venv's bin, which is on PATH already only when the venv is activated.
      _ensure_uv_add_path "$(dirname "$py")"
    else
      echo "uv not found; installing it with '$py -m pip install --user uv'..." >&2

      # PIP_BREAK_SYSTEM_PACKAGES bypasses PEP 668's externally-managed guard, which
      # Debian and Ubuntu enable. Safe here: `--user` leaves system site-packages
      # alone. Upgrading pip first matters because one predating PEP 600 (20.0.2 on
      # Ubuntu 20.04) mis-resolves uv's wheel tags.
      PIP_BREAK_SYSTEM_PACKAGES=1 "$py" -m pip install --user -q --upgrade pip >>"$log" 2>&1 || true
      # --force-reinstall because pip no-ops when site-packages already has uv,
      # leaving nothing for the user bin to shadow a broken uv on PATH with.
      PIP_BREAK_SYSTEM_PACKAGES=1 "$py" -m pip install --user -q --force-reinstall uv >>"$log" 2>&1 || true

      _ensure_uv_add_user_bin "$py"
    fi
  fi

  # A pip install above may have placed a fresh uv on PATH, or a shadow entry
  # earlier in PATH may have been cached by bash. Clear the hash so bash re-scans
  # PATH rather than reusing the binary it found before the install.
  hash -r
  uv --version >/dev/null 2>&1 && return 0

  echo "uv not found; installing it into a virtual environment at $venv_dir..." >&2

  # --clear replaces a previously broken venv; a working one was found already.
  # Native Windows interpreters resolve /cygdrive/... against the current
  # drive's root, so hand them a C:/ style path; see _ensure_uv_scope_paths.
  declare venv_arg="$venv_dir"
  if [ "${OSTYPE:-}" = cygwin ]; then
    venv_arg="$(cygpath -m "$venv_dir")"
  fi
  "$py" -m venv --clear "$venv_arg" >>"$log" 2>&1 || return 0

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
# - PATH (~/.local/bin, the active venv's bin dir, pip's `--user` script directory, and a fallback venv's bin dir)
# - UV_TOOL_DIR (only when $DRIVERS_TOOLS is set)
# - UV_CACHE_DIR, UV_PYTHON_INSTALL_DIR (additionally require $CI to be set)
# - UV_PYTHON (when the workspace floor is known and a qualifying interpreter exists)
#
# Looks everywhere uv may already be, and only then hands off to
# _ensure_uv_install, which tries the active venv, then `pip install --user`,
# then a fallback venv.
#
# On success, also pins uv's interpreter to a floor-qualifying host
# interpreter, or installs a uv-managed one when none qualifies. See
# _ensure_uv_floor_bootstrap.
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

  declare py="" current_py="" toolchain_py="" candidate=""
  # The platform-specific "Current" path, set even when a venv is active:
  # the venv may sit below the floor while Current does not, and only the
  # fallback loop looks there.
  case "${OSTYPE:-}" in
  cygwin) current_py="C:/python/Current/python.exe" ;;
  darwin*) current_py="/Library/Frameworks/Python.Framework/Versions/Current/bin/python3" ;;
  *) current_py="/opt/python/Current/bin/python3" ;;
  esac

  # Use the active venv's interpreter so uv installs into it; see the in-venv
  # branch of _ensure_uv_install. Otherwise prefer the Current and toolchain
  # interpreters over the system python3, which can be old (rhel82-arm64: 3.6)
  # or absent.
  #
  # The workspace's Python floor (e.g. "3.11") from the root pyproject.toml's
  # requires-python. Fails soft, falling back to uv's own interpreter
  # handling when it cannot be parsed.
  declare floor="" floor_major="" floor_minor="" floor_py=""
  floor="$(_ensure_uv_min_python || true)"
  if [ -n "$floor" ]; then
    floor_major="${floor%%.*}"
    floor_minor="${floor#*.}"
  fi
  if [ -n "${VIRTUAL_ENV:-}" ]; then
    if [ -x "$VIRTUAL_ENV/bin/python" ]; then
      py="$VIRTUAL_ENV/bin/python"
    elif [ -x "$VIRTUAL_ENV/Scripts/python.exe" ]; then
      py="$VIRTUAL_ENV/Scripts/python.exe"
    fi
    if [ -n "$py" ] && [ -n "$floor" ] && _ensure_uv_meets_floor "$py" "$floor_major" "$floor_minor"; then
      floor_py="$py"
    fi
  fi
  if [ -z "$py" ]; then
    if [ -x "$current_py" ] &&
      "$current_py" -c 'import pip; import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
      py="$current_py"
      if [ -n "$py" ] && [ -n "$floor" ] && _ensure_uv_meets_floor "$py" "$floor_major" "$floor_minor"; then
        floor_py="$py"
      fi
    else
      toolchain_py="$(compgen -G '/opt/mongodbtoolchain/v*/bin/python3' | sort -V | tail -n1)" || true
      if [ -n "$toolchain_py" ] && [ -x "$toolchain_py" ]; then
        py="$toolchain_py"
        if [ -n "$py" ] && [ -n "$floor" ] && _ensure_uv_meets_floor "$py" "$floor_major" "$floor_minor"; then
          floor_py="$py"
        fi
      elif command -v python3 >/dev/null 2>&1; then
        py="$(command -v python3)"
      elif command -v python >/dev/null 2>&1; then
        py="$(command -v python)"
      fi
    fi
  fi

  # Find a pin target even when the bootstrap pick settled for an older
  # interpreter (current_py 3.10, toolchain 3.13).
  if [ -n "$floor" ] && [ -z "$floor_py" ]; then
    if [ -n "$py" ] && _ensure_uv_meets_floor "$py" "$floor_major" "$floor_minor"; then
      floor_py="$py"
    else
      # Newest first, so a prerelease newest does not hide an older toolchain
      # that is a final release meeting the floor.
      declare -a candidates=("$current_py")
      while IFS= read -r candidate; do
        candidates+=("$candidate")
      done < <(compgen -G '/opt/mongodbtoolchain/v*/bin/python3' | sort -Vr)
      candidates+=("$(command -v python3 2>/dev/null || true)" "$(command -v python 2>/dev/null || true)")
      for candidate in "${candidates[@]}"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ] &&
          _ensure_uv_meets_floor "$candidate" "$floor_major" "$floor_minor"; then
          floor_py="$candidate"
          break
        fi
      done
    fi
  fi

  # None of these is reliably on PATH in a fresh shell. ~/.local/bin is where uv's
  # own installer puts it and is off the default PATH on some hosts (RHEL7 root
  # shells), and the rest are where an earlier ensure_uv call put it. Scripts is the
  # Windows spelling of bin.
  [ -n "${HOME:-}" ] && _ensure_uv_add_path "$HOME/.local/bin"
  _ensure_uv_add_path "$venv_dir/bin"
  _ensure_uv_add_path "$venv_dir/Scripts"
  [ -n "$py" ] && _ensure_uv_add_user_bin "$py"

  if uv --version >/dev/null 2>&1; then
    _ensure_uv_scope_paths
    _ensure_uv_floor_bootstrap "$floor_major" "$floor_minor" "$floor_py"
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

  # The fallback venv above added its bin to PATH; re-resolve uv so bash does not
  # keep pointing at whatever it found before the install.
  hash -r
  if uv --version >/dev/null 2>&1; then
    _ensure_uv_scope_paths
    _ensure_uv_floor_bootstrap "$floor_major" "$floor_minor" "$floor_py"
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
