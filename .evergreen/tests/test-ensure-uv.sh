#!/usr/bin/env bash
#
# Integration tests for ensure-uv.sh.
#
# Every case runs against a real interpreter. uv installs the pinned ones and the
# host supplies the rest, so nothing here imitates a host shape and no case can
# pass against a fiction. Each runs in a sandbox with its own HOME, TMPDIR and
# DRIVERS_TOOLS, and a PATH that hides any uv already on this machine.
set -eu

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENSURE_UV="$SCRIPT_DIR/../ensure-uv.sh"

failures=0

# uv installs the pinned interpreters, so one has to be reachable before the
# sandboxes hide it. Bootstrapping it here rather than requiring setup.sh first
# keeps this runnable from a clean checkout, which is how GitHub Actions runs it.
if ! command -v uv >/dev/null 2>&1; then
  echo "No uv on PATH; bootstrapping one to install the pinned interpreters."
  # shellcheck source=/dev/null
  . "$ENSURE_UV"
  ensure_uv || exit 1
fi

# pinned_python
#
# Absolute path to a uv-managed CPython $1, installing it if it is not present.
pinned_python() {
  if ! uv python install "$1" >/dev/null 2>&1; then
    echo "ERROR: uv could not install CPython $1 on this platform." >&2
    return 1
  fi
  uv python find "$1"
}

# check
#
# Run case $1 in a sandbox, where $2 sets the scenario up and $3 asserts on the
# result. Both see $sandbox, and $ensure_uv_status holds what ensure_uv returned
# so a case can assert on a refusal.
check() {
  local name="$1" setup="$2" assert="$3"
  local sandbox
  sandbox=$(mktemp -d)

  if (
    set -eu
    export sandbox
    mkdir -p "$sandbox/bin" "$sandbox/home" "$sandbox/tmp" "$sandbox/drivers-tools"

    # A pared-down PATH and a sandbox DRIVERS_TOOLS, so neither a uv already
    # installed here nor the real tree can satisfy or absorb the call. Set before
    # the setup runs, so a case that activates a venv keeps it on PATH.
    export PATH="$sandbox/bin:/usr/bin:/bin"
    export HOME="$sandbox/home"
    export TMPDIR="$sandbox/tmp"
    export DRIVERS_TOOLS="$sandbox/drivers-tools"
    unset CI

    eval "$setup"

    # shellcheck source=/dev/null
    . "$ENSURE_UV"
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

# uv's own Requires-Python is >=3.8, and ensure_uv only has to bootstrap uv: the
# 3.9 floor in .evergreen/pyproject.toml belongs to the projects uv then runs, and
# uv fetches an interpreter for those itself. Pinning the oldest interpreter uv
# supports means a future uv that drops 3.8 fails here rather than on a host.
PINNED_PY38="$(pinned_python 3.8)"
export PINNED_PY38

check "installs uv with pip --user" '
  export DRIVERS_TOOLS_PYTHON="$PINNED_PY38"
' '
  [ "$ensure_uv_status" -eq 0 ] || { echo "ensure_uv failed with a 3.8 interpreter"; exit 1; }
  uv --version >/dev/null || { echo "no working uv on PATH"; exit 1; }
  base="$("$DRIVERS_TOOLS_PYTHON" -m site --user-base)"
  [ -x "$base/bin/uv" ] || { echo "expected a --user install under $base"; exit 1; }
'

# How the Node OIDC tests call ensure_uv. pip refuses --user inside a venv, and
# the venv is the right target there anyway.
check "installs into the active venv when --user is refused" '
  "$PINNED_PY38" -m venv "$sandbox/venv"
  # shellcheck source=/dev/null
  . "$sandbox/venv/bin/activate"
  export DRIVERS_TOOLS_PYTHON="$sandbox/venv/bin/python"
' '
  [ "$ensure_uv_status" -eq 0 ] || { echo "ensure_uv failed inside a venv"; exit 1; }
  [ -x "$sandbox/venv/bin/uv" ] || {
    echo "expected uv in the active venv, got $(command -v uv)"; exit 1
  }
'

echo "Testing ensure_uv reuse of an existing uv ..."

# A later script in a fresh shell has to find the uv an earlier one installed.
# $DRIVERS_TOOLS/.bin is where handle-paths.sh looks, so give the second call only
# that and check it stays quiet: ensure_uv announces every install it attempts.
check "reuses the published uv instead of installing again" '
  export DRIVERS_TOOLS_PYTHON="$PINNED_PY38"
' '
  [ -x "$DRIVERS_TOOLS/.bin/uv" ] || { echo "expected uv published to $DRIVERS_TOOLS/.bin"; exit 1; }
  PATH="$DRIVERS_TOOLS/.bin:/usr/bin:/bin"
  second="$(ensure_uv 2>&1)" || { echo "the second call failed with a published uv available"; exit 1; }
  case "$second" in
  *"installing it with"*) echo "reinstalled instead of reusing: $second"; exit 1 ;;
  esac
'

echo "Testing ensure_uv refusal ..."

# ensure_uv has to refuse a host it cannot rescue rather than report success and
# leave callers without uv. This needs an interpreter uv publishes nothing for,
# and uv installs nothing below its own 3.8 floor, so it takes a host that
# genuinely has an old python3. rhel82-arm64's platform python3 is 3.6, which is
# the host PYTHON-6005 was filed for.
PINNED_OLD_PY=""
for candidate in /usr/bin/python3 "$(command -v python3 2>/dev/null || true)"; do
  [ -n "$candidate" ] && [ -x "$candidate" ] || continue
  if ! "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)'; then
    PINNED_OLD_PY="$candidate"
    break
  fi
done
export PINNED_OLD_PY

if [ -n "$PINNED_OLD_PY" ]; then
  check "fails when the only interpreter is too old for uv" '
    export DRIVERS_TOOLS_PYTHON="$PINNED_OLD_PY"
  ' '
    [ "$ensure_uv_status" -ne 0 ] || {
      echo "expected a refusal, got success and uv at $(command -v uv || echo none)"; exit 1
    }
  '
else
  echo "  skip: no python3 below 3.8 on this host, which this case needs"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures ensure_uv test(s) failed." >&2
  exit 1
fi
echo "All ensure_uv tests passed."
