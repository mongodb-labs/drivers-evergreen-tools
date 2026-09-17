#!/usr/bin/env bash
#
# Regression tests for two ensure_uv install cases that no VM image reproduces:
# inside an active venv, and pip-without-venv. Runs in a private HOME/TMPDIR and
# skips on hosts that cannot reproduce a case.
set -eu -o pipefail

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "$SCRIPT_DIR/../handle-paths.sh"

case "$(uname -s)" in
  Linux | Darwin)
    VENV_SUBDIR=bin
    UV_NAME=uv
    ;;
  MINGW* | MSYS* | CYGWIN*)
    VENV_SUBDIR=Scripts
    UV_NAME=uv.exe
    ;;
  *)
    echo "test-ensure-uv.sh: unsupported platform; skipping."
    make -C "$DRIVERS_TOOLS" test
    exit 0
    ;;
esac

# ensure_uv only uses a Python 3.8+ interpreter, so build its test venv with one.
# Try candidates in ensure_uv's own order: the python toolchain's Current
# interpreter, the MongoDB toolchain, then the system.
case "$(uname -s)" in
  Linux) CURRENT_PY=/opt/python/Current/bin/python3 ;;
  Darwin) CURRENT_PY="/Library/Frameworks/Python.Framework/Versions/Current/bin/python3" ;;
  *) CURRENT_PY="C:/python/Current/python.exe" ;;
esac
PY_BIN=""
for c in "$CURRENT_PY" $(compgen -G '/opt/mongodbtoolchain/v*/bin/python3' | sort -Vr) python3 python; do
  if command -v "$c" >/dev/null 2>&1 && "$(command -v "$c")" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
    PY_BIN="$(command -v "$c")"
    break
  fi
done

if [ -z "$PY_BIN" ] || ! "$PY_BIN" -m pip --version >/dev/null 2>&1; then
  echo "test-ensure-uv.sh: no Python 3.8+ with pip; skipping."
  make -C "$DRIVERS_TOOLS" test
  exit 0
fi

# Native Windows interpreters resolve /cygdrive/... against the current drive's
# root, so hand them a C:/ style path.
to_py_path() {
  if [ "${OSTYPE:-}" = cygwin ]; then
    cygpath -m "$1"
  else
    printf '%s' "$1"
  fi
}

ENSURE_UV="$SCRIPT_DIR/../ensure-uv.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ensure-uv-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# Isolate each case from the host: private HOME/TMPDIR, a temp DRIVERS_TOOLS
# (uv's cache/tool dirs live under it), cleared interpreter hints, and no
# working uv already on PATH.
reset_env() {
  mkdir -p "$WORK/home" "$WORK/tmp"
  export HOME="$WORK/home"
  export TMPDIR="$WORK/tmp"
  # A fresh tools dir per case so one case's cache/tool dirs do not satisfy the
  # next.
  local tools_dir
  tools_dir="$(mktemp -d "$WORK/tools.XXXXXX")"
  export DRIVERS_TOOLS="$tools_dir"
  # Isolate pip's user install dir too; it is %APPDATA% on Windows, not HOME.
  local user_base py_user_base
  user_base="$(mktemp -d "$WORK/pyuserbase.XXXXXX")"
  py_user_base="$(to_py_path "$user_base")"
  export PYTHONUSERBASE="$py_user_base"
  unset DRIVERS_TOOLS_PYTHON VIRTUAL_ENV
  # A failing uv stub forces an install while keeping co-located tools visible.
  local stub_dir="$WORK/stub"
  mkdir -p "$stub_dir"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$stub_dir/uv"
  chmod +x "$stub_dir/uv"
  export PATH="$stub_dir:$PATH"
}

# Fail unless a uv is on PATH and runs.
assert_uv_available() {
  command -v uv >/dev/null 2>&1 || { echo "uv is not on PATH" >&2; return 1; }
  uv --version >/dev/null || { echo "uv does not run" >&2; return 1; }
}

test_inside_active_venv() {
  local outer="$WORK/outer"
  local venv_bin="$outer/$VENV_SUBDIR"
  # Probe real venv creation: help text is no proof (Debian without
  # python3-venv). Skip this case only, so the next one still runs.
  if ! "$PY_BIN" -m venv --clear "$(to_py_path "$outer")" >/dev/null 2>&1; then
    echo "Testing ensure_uv inside an active venv ... skipped (venv creation unavailable)."
    return 0
  fi
  echo "Testing ensure_uv inside an active venv ..."
  (
    reset_env
    export VIRTUAL_ENV="$outer"
    export PATH="$venv_bin:$PATH"
    # shellcheck source=../ensure-uv.sh
    . "$ENSURE_UV"
    ensure_uv
    assert_uv_available
    # uv should be installed into the active venv and be the uv on PATH.
    [ -x "$venv_bin/$UV_NAME" ] || {
      echo "expected $UV_NAME installed into the active venv" >&2
      return 1
    }
    # Cygwin bash reports `command -v` results without the .exe suffix.
    found="$(command -v uv)"
    [ "${found%.exe}" = "${venv_bin}/${UV_NAME%.exe}" ] || {
      echo "expected uv on PATH from the active venv, got $found" >&2
      return 1
    }
  )
  echo "Testing ensure_uv inside an active venv ... done."
}

test_no_venv_module() {
  local stub="$WORK/novenv"
  local py_stub
  py_stub="$(to_py_path "$stub")"
  mkdir -p "$stub/venv"
  printf 'raise ImportError("venv disabled for test")\n' >"$stub/venv/__init__.py"
  echo "Testing ensure_uv without a venv module ..."
  (
    reset_env
    export PYTHONPATH="$py_stub"
    # The pre-resolved interpreter, already vetted for pip and 3.8+ above.
    if "$PY_BIN" -c 'import venv' >/dev/null 2>&1; then
      echo "expected the venv module to be disabled; this test is no longer testing anything" >&2
      exit 1
    fi
    # shellcheck source=../ensure-uv.sh
    . "$ENSURE_UV"
    ensure_uv
    assert_uv_available
    # pip is the only way through, so the venv fallback must not have run.
    if [ -e "$WORK/tmp/drivers-tools-uv-venv" ]; then
      echo "expected uv from the pip path, not the fallback venv" >&2
      return 1
    fi
  )
  echo "Testing ensure_uv without a venv module ... done."
}

test_inside_active_venv
test_no_venv_module

make -C "$DRIVERS_TOOLS" test
