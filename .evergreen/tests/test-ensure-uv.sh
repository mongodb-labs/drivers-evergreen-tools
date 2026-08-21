#!/usr/bin/env bash
#
# Tests for ensure-uv.sh.
#
# Each case pins a stub interpreter through DRIVERS_TOOLS_PYTHON and covers what
# ensure_uv does with the one it picks. Pinning matters: without it the real
# MongoDB toolchain on an Evergreen host wins over anything in the sandbox.
#
# Which interpreter a distro actually offers is a property of the distro, so no
# case tries to imitate one. The build variants cover that on real hosts, and the
# kms variants cover the remote VMs.
set -eu

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
# Absolute, because the stubs exec it from wherever ensure_uv runs them.
STUB_PYTHON="$(cd "$SCRIPT_DIR" && pwd)/stub-python.sh"

failures=0

# make_python
#
# Write a stub interpreter to $1 reporting version $2, with the capabilities
# named in $3 ("pip", "venv"), reporting $4 as its `--user` base.
#
# The stub is a wrapper that hands off to stub-python.sh, which holds the
# behavior and documents the variables. An install drops a `uv` into the target
# bin directory, and that uv names the interpreter it came from, so a case can
# assert which one ensure_uv picked rather than just that it found something.
make_python() {
  local path="$1" version="$2" caps="$3" user_base="$4"

  mkdir -p "$(dirname "$path")"
  {
    printf '#!/usr/bin/env bash\n'
    printf '# Stub interpreter: Python %s, capabilities [%s].\n' "$version" "$caps"
    printf 'export STUB_VERSION=%q STUB_CAPS=%q STUB_USER_BASE=%q STUB_ORIGIN=%q\n' \
      "$version" "$caps" "$user_base" "$path"
    printf 'exec %q "$@"\n' "$STUB_PYTHON"
  } >"$path"
  chmod +x "$path"
}

# make_uv
#
# Write a stub uv reporting version $2 to $1, standing in for one a previous run
# already installed.
make_uv() {
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\necho "uv %s (from a previous run)"\n' "$2" >"$1"
  chmod +x "$1"
}

# check
#
# Run case $1 in a sandbox. $2 sets the scenario up, $3 asserts on the result.
# Both run with $sandbox set. ensure_uv has already been called and its exit
# status is in $ensure_uv_status, so a case can assert on a refusal too.
check() {
  local name="$1" setup="$2" assert="$3"
  local sandbox
  sandbox=$(mktemp -d)

  if (
    set -eu
    export sandbox
    mkdir -p "$sandbox/bin" "$sandbox/home" "$sandbox/tmp"
    eval "$setup"

    # A pared-down PATH, so this host's own uv cannot quietly satisfy the call.
    export PATH="$sandbox/bin:/usr/bin:/bin"
    export HOME="$sandbox/home"
    export TMPDIR="$sandbox/tmp"
    unset CI

    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/../ensure-uv.sh"
    ensure_uv_status=0
    ensure_uv || ensure_uv_status=$?
    export ensure_uv_status
    eval "$assert"
  ) >"$sandbox/out.log" 2>&1; then
    echo "  ok: $name"
  else
    echo "  FAIL: $name"
    sed 's/^/    /' "$sandbox/out.log"
    failures=$((failures + 1))
  fi

  rm -rf "$sandbox"
}

echo "Testing ensure_uv install methods ..."

check "installs uv with pip --user" '
  make_python "$sandbox/bin/python3" 3.11.9 pip,venv "$sandbox/platform-user-base"
  export DRIVERS_TOOLS_PYTHON="$sandbox/bin/python3"
' '
  uv --version | grep -q "$sandbox/bin/python3, --user" || {
    echo "expected a --user install by the stub, got: $(uv --version)"; exit 1
  }
'

# How the Node OIDC tests call ensure_uv. pip refuses --user inside a venv, and
# the venv is the right target there anyway.
check "installs into the active venv when --user is refused" '
  make_python "$sandbox/bin/python3" 3.11.9 pip,venv,invenv "$sandbox/platform-user-base"
  export DRIVERS_TOOLS_PYTHON="$sandbox/bin/python3"
' '
  uv --version | grep -q "$sandbox/bin/python3, venv" || {
    echo "expected an install without --user, got: $(uv --version)"; exit 1
  }
'

# Legacy support for KMS VMs provisioned before PYTHON-5985 added python3-pip.
# Debian refuses ensurepip outside a venv, so a venv is the only route there.
# DRIVERS-XXXX (placeholder, not yet filed) tracks getting those pins past
# PYTHON-5985. Delete this case when it closes.
check "legacy: builds a venv when the interpreter has no pip" '
  make_python "$sandbox/bin/python3" 3.9.2 venv "$sandbox/platform-user-base"
  export DRIVERS_TOOLS_PYTHON="$sandbox/bin/python3"
' '
  uv --version | grep -q "$sandbox/bin/python3" || {
    echo "expected uv from the venv, got: $(uv --version)"; exit 1
  }
'

echo "Testing ensure_uv reuse of an existing uv ..."

# ~/.local/bin is off the default PATH on some hosts, so an existing uv there
# has to be found rather than reinstalled.
check "reuses a uv already installed under ~/.local/bin" '
  make_uv "$sandbox/home/.local/bin/uv" 0.11.8
' '
  case "$(uv --version)" in
  "uv 0.11.8"*) ;;
  *) echo "expected the existing uv to be reused, got: $(uv --version)"; exit 1 ;;
  esac
'

echo "Testing ensure_uv install location ..."

check "installs uv into \$DRIVERS_TOOLS/.bin" '
  make_python "$sandbox/bin/python3" 3.11.9 pip,venv "$sandbox/platform-user-base"
  export DRIVERS_TOOLS_PYTHON="$sandbox/bin/python3"
  export DRIVERS_TOOLS="$sandbox/drivers-tools"
' '
  [ -x "$sandbox/drivers-tools/.bin/uv" ] || {
    echo "expected uv in \$DRIVERS_TOOLS/.bin, found: $(command -v uv)"; exit 1
  }
'

echo "Testing ensure_uv refusal ..."

# The failure PYTHON-6005 reported, and the one thing the cases above cannot
# show: with no interpreter it can use, ensure_uv has to fail rather than report
# success and leave callers with a uv that is not there. A real host cannot be
# asked for this on demand, so it stays a stub.
check "fails when the only interpreter is too old for uv" '
  make_python "$sandbox/bin/python3" 3.6.8 pip,venv "$sandbox/platform-user-base"
  export DRIVERS_TOOLS_PYTHON="$sandbox/bin/python3"
' '
  [ "$ensure_uv_status" -ne 0 ] || {
    echo "expected ensure_uv to fail, got 0 and uv at: $(command -v uv || echo none)"; exit 1
  }
'

if [ "$failures" -ne 0 ]; then
  echo "$failures ensure_uv test(s) failed." >&2
  exit 1
fi
echo "All ensure_uv tests passed."
