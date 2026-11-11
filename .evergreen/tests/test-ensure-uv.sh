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
  CYGWIN*)
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
  unset DRIVERS_TOOLS_PYTHON VIRTUAL_ENV UV_PYTHON
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

# --- Interpreter-selection cases ---
#
# These do not install anything: a recording stub uv succeeds where the
# failing stub above forces an install, and logs the UV_PYTHON pin and the
# managed-install calls it sees.

# A pure-bash interpreter stand-in: passes the pip probe, and the floor
# probe exits with $2 (0 passes it).
make_fake_py() { # path floor_rc
  cat >"$1" <<EOF
#!/usr/bin/env bash
code="\${2:-}"
case "\$code" in
*sysconfig*) exit 0 ;;
*releaselevel*) exit $2 ;;
*) exit 0 ;;
esac
EOF
  chmod +x "$1"
}

# A real interpreter reporting 3.14.0rc1: exercises the releaselevel
# rejection, which a pure-bash fake cannot reach.
make_prerelease_py() { # path
  {
    printf '#!%s\n' "$PY_BIN"
    printf 'import collections, sys\n'
    printf 'sys.version_info = collections.namedtuple("version_info", "major minor micro releaselevel serial")(3, 14, 0, "rc1", 0)\n'
    printf 'exec(sys.argv[2])\n'
  } >"$1"
  chmod +x "$1"
}

# A PyPy-like interpreter: meets the floor's version and release level, so
# only the implementation check can reject it.
make_pypy_py() { # path
  cat >"$1" <<'EOF'
#!/usr/bin/env bash
code="${2:-}"
case "$code" in
*sysconfig*) exit 0 ;;
*implementation*) exit 1 ;;
*releaselevel*) exit 0 ;;
*) exit 0 ;;
esac
EOF
  chmod +x "$1"
}

make_recording_stub() {
  # Exported for the stub, which runs as a child process. Truncated here so
  # each case's assertions read only that case's calls.
  export STUB_LOG="$WORK/stub-log"
  : >"$STUB_LOG"
  cat >"$WORK/stub/uv" <<'EOF'
#!/usr/bin/env bash
{
  printf 'uv-python=%s\n' "${UV_PYTHON:-<unset>}"
  if [ "${1:-}" = python ] && [ "${2:-}" = install ]; then
    printf 'uv-python-install=%s\n' "${3:-?}"
  fi
} >>"${STUB_LOG:?}"
exit 0
EOF
  chmod +x "$WORK/stub/uv"
}

# The selection loop also probes the host's Current and toolchain
# interpreters, which a case cannot hide from it. Cases whose outcome depends
# on no hidden qualifier existing skip when one does.
host_hides_qualifier() {
  local c
  for c in "$CURRENT_PY" $(compgen -G '/opt/mongodbtoolchain/v*/bin/python3' | sort -Vr); do
    if [ -x "$c" ] && "$c" -c 'import sys; sys.exit(0 if sys.implementation.name == "cpython" and sys.version_info >= (3, 11) and sys.version_info.releaselevel == "final" else 1)' >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

# A floor-qualifying host interpreter is pinned for uv, no managed python is
# downloaded, and the caller's command lookup is left alone.
test_pin_qualifying_host() {
  echo "Testing ensure_uv pins a qualifying host interpreter ..."
  (
    reset_env
    make_recording_stub
    local fake="$WORK/fakepy/bin"
    mkdir -p "$fake"
    make_fake_py "$fake/python3" 0
    export PATH="$fake:$PATH"
    local py_before
    py_before="$(command -v python3)"
    # shellcheck source=../ensure-uv.sh
    . "$ENSURE_UV"
    ensure_uv
    # The pin lives in the environment: the stub only logs when uv runs,
    # and nothing runs uv after the bootstrap.
    local pinned="${UV_PYTHON:-}"
    [ -n "$pinned" ] || { echo "expected UV_PYTHON pinned" >&2; return 1; }
    "$pinned" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) and sys.version_info.releaselevel == "final" else 1)' >/dev/null 2>&1 || {
      echo "expected the pinned interpreter to satisfy the floor, got $pinned" >&2
      return 1
    }
    [ -z "$(grep '^uv-python-install=' "$STUB_LOG" || true)" ] || {
      echo "expected no managed download with a qualifying host interpreter" >&2
      return 1
    }
    [ "$(command -v python3)" = "$py_before" ] || {
      echo "expected PATH lookup unchanged, python3 now resolves to $(command -v python3)" >&2
      return 1
    }
    # With no hidden qualifier, the PATH interpreter is the one selected.
    if ! host_hides_qualifier; then
      [ "$pinned" = "$fake/python3" ] || { echo "expected the PATH interpreter pinned, got $pinned" >&2; return 1; }
    fi
  )
  echo "Testing ensure_uv pins a qualifying host interpreter ... done."
}

# With no interpreter meeting the floor, a uv-managed one is installed and
# nothing is pinned. $2 makes the stand-in's floor probe; $3 names the case.
test_fallback_to_managed() { # fake_path floor_ok label
  if host_hides_qualifier; then
    echo "Testing ensure_uv $3 ... skipped (the host has a hidden qualifier)."
    return 0
  fi
  echo "Testing ensure_uv $3 ..."
  (
    reset_env
    make_recording_stub
    mkdir -p "$(dirname "$1")"
    if [ "$2" = prerelease ]; then
      make_prerelease_py "$1"
    elif [ "$2" = pypy ]; then
      make_pypy_py "$1"
    else
      make_fake_py "$1" 1
    fi
    local fake_dir
    fake_dir="$(dirname "$1")"
    # Shadow both interpreter names: ensure_uv probes python3, then python,
    # and a host qualifying through the other name would mask the fallback.
    cp "$1" "$fake_dir/python"
    export PATH="$fake_dir:$PATH"
    # shellcheck source=../ensure-uv.sh
    . "$ENSURE_UV"
    ensure_uv
    grep -q '^uv-python-install=' "$STUB_LOG" || { echo "expected a managed install" >&2; return 1; }
    grep -q '^uv-python=<unset>$' "$STUB_LOG" || { echo "expected no pin without a qualifying host interpreter" >&2; return 1; }
  )
  echo "Testing ensure_uv $3 ... done."
}

# The floor lookup must survive a directory change after sourcing by a
# relative path.
test_root_survives_cd() {
  echo "Testing ensure_uv after changing directories ..."
  (
    reset_env
    make_recording_stub
    local fake="$WORK/fakepy/bin"
    mkdir -p "$fake"
    make_fake_py "$fake/python3" 0
    export PATH="$fake:$PATH"
    cd "$SCRIPT_DIR"
    # Relative source path: the trigger for the stale-root case.
    # shellcheck source=../ensure-uv.sh
    . ../ensure-uv.sh
    cd "$WORK"
    ensure_uv
    # Assert the environment: the stub only logs when uv runs, and nothing
    # runs uv after the bootstrap, so a log read cannot see the pin.
    [ -n "${UV_PYTHON:-}" ] || { echo "expected the floor to parse and pin after the directory change" >&2; return 1; }
  )
  echo "Testing ensure_uv after changing directories ... done."
}

test_pin_qualifying_host
test_fallback_to_managed "$WORK/belowfloor/bin/python3" final "falls back to a managed python below the floor"
test_fallback_to_managed "$WORK/prerelease/bin/python3" prerelease "falls back to a managed python on a prerelease"
test_fallback_to_managed "$WORK/pypy/bin/python3" pypy "falls back to a managed python on PyPy"
test_root_survives_cd

make -C "$DRIVERS_TOOLS" test
