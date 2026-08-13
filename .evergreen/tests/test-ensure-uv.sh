#!/usr/bin/env bash
#
# Tests for ensure-uv.sh.
#
# The first half pins ensure_uv to a stub interpreter through
# DRIVERS_TOOLS_PYTHON, covering what it does with the interpreter it is handed.
# Which interpreter a distro actually offers is find_python3's problem, so the
# second half runs on real images.
set -eu

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")

failures=0

# make_python
#
# Write a stub interpreter to $1 reporting version $2, with the capabilities
# named in $3 ("pip", "venv", "brokenvenv"), reporting $4 as its `--user` base.
#
# It answers only what ensure_uv asks. An install drops a `uv` into the target
# bin directory, and that uv names the interpreter it came from, so a case can
# assert which one ensure_uv picked rather than just that it found something.
make_python() {
  local path="$1" version="$2" caps="$3" user_base="$4"

  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
#!/usr/bin/env bash
# Stub interpreter: Python $version, capabilities [$caps].
version="$version"
major_minor="${version%.*}"
caps="$caps"
user_base="$user_base"
origin="$path"
EOF
  cat >>"$path" <<'EOF'
set -u

# uv publishes no distribution below Python 3.8, so an older interpreter fails
# here the way it does on a real host: pip and venv both find nothing.
supports_uv() {
  [ "$(printf '%s\n' 3.8 "$major_minor" | sort -V | head -n1)" = "3.8" ]
}

has() { case ",$caps," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

no_distribution() {
  echo "ERROR: Could not find a version that satisfies the requirement uv (from versions: none)" >&2
  echo "ERROR: No matching distribution found for uv" >&2
  exit 1
}

# Drop a working uv into $1. $origin survives into the venv copy below, so a uv
# installed by a venv still names the interpreter that venv was built from.
install_uv_into() {
  mkdir -p "$1"
  {
    printf '#!/bin/sh\n'
    printf 'echo "uv 0.12.3 (from %s)"\n' "$origin"
  } >"$1/uv"
  chmod +x "$1/uv"
}

case "${1:-}" in
--version)
  echo "Python $version"
  ;;
-c)
  # ensure_uv's only -c call is the version check.
  supports_uv
  ;;
-m)
  case "${2:-}" in
  site)
    echo "$user_base"
    ;;
  pip)
    has pip || exit 1
    if [ "${3:-}" = "--version" ]; then
      echo "pip 24.0 from $user_base (python $version)"
      exit 0
    fi
    # Anything other than an install of uv, e.g. upgrading pip, is a no-op.
    for arg in "$@"; do
      if [ "$arg" = "uv" ]; then
        supports_uv || no_distribution
        install_uv_into "$user_base/bin"
        exit 0
      fi
    done
    ;;
  venv)
    # Debian without python3-venv: venv builds the directory, then fails in
    # ensurepip, leaving a pip-less interpreter behind on PATH.
    if has brokenvenv; then
      venv_dir="${*: -1}"
      mkdir -p "$venv_dir/bin"
      printf '#!/bin/sh\nexit 1\n' >"$venv_dir/bin/python3"
      chmod +x "$venv_dir/bin/python3"
      echo "ensurepip is not available" >&2
      exit 1
    fi
    has venv || exit 1
    supports_uv || no_distribution
    # Seed the venv with an interpreter that installs into the venv's own bin.
    # It always has pip, even when the base one did not: seeding pip through
    # ensurepip is why a host with venv but no pip can still get uv.
    venv_dir="${*: -1}"
    mkdir -p "$venv_dir/bin"
    sed -e "s|^user_base=.*|user_base=\"$venv_dir\"|" \
        -e 's|^caps=.*|caps="pip,venv"|' "$0" >"$venv_dir/bin/python"
    chmod +x "$venv_dir/bin/python"
    ;;
  *)
    exit 1
    ;;
  esac
  ;;
*)
  exit 1
  ;;
esac
EOF
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
# Both run with $sandbox set and ensure_uv already called.
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

    . "$SCRIPT_DIR/../ensure-uv.sh"
    ensure_uv
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

echo "Testing ensure_uv interpreter selection ..."

check "installs uv with the interpreter find_python3 selected" '
  make_python "$sandbox/toolchain/v4/bin/python3" 3.10.9 pip,venv "$sandbox/toolchain-user-base"
  export DRIVERS_TOOLS_PYTHON="$sandbox/toolchain/v4/bin/python3"
' '
  uv --version | grep -q toolchain || {
    echo "expected uv from the selected interpreter, got: $(uv --version)"; exit 1
  }
'

# Evergreen's debian11 images have pip but no python3-venv. The failed venv
# leaves a pip-less interpreter on PATH, so the pip fallback has to keep using
# the interpreter that was selected, not whatever `python3` now resolves to.
check "debian 11: falls back to pip when the venv module is broken" '
  make_python "$sandbox/bin/python3" 3.9.2 pip,brokenvenv "$sandbox/platform-user-base"
  export DRIVERS_TOOLS_PYTHON="$sandbox/bin/python3"
' '
  uv --version | grep -q "$sandbox/bin/python3" || {
    echo "expected uv from the selected python3 via pip, got: $(uv --version)"; exit 1
  }
'

# The mirror of the case above, and what the deadsnakes docker images look like.
check "installs uv through the venv when the interpreter has no pip" '
  make_python "$sandbox/bin/python3" 3.11.9 venv "$sandbox/platform-user-base"
  export DRIVERS_TOOLS_PYTHON="$sandbox/bin/python3"
' '
  uv --version | grep -q "$sandbox/bin/python3" || {
    echo "expected uv from the venv, got: $(uv --version)"; exit 1
  }
'

echo "Testing ensure_uv reuse of an existing uv ..."

# uv 0.10.0 stopped invalidating the lockfile versions after an exclude-newer
# change, which drivers-tools relies on, so an older uv has to be replaced.
check "replaces a uv older than 0.10" '
  make_uv "$sandbox/home/.local/bin/uv" 0.9.2
  make_python "$sandbox/bin/python3" 3.11.9 pip,venv "$sandbox/platform-user-base"
  export DRIVERS_TOOLS_PYTHON="$sandbox/bin/python3"
' '
  got=$(uv --version)
  case "$got" in
  "uv 0.9.2"*) echo "expected the too-old uv to be replaced, still got: $got"; exit 1 ;;
  esac
'

check "reuses a uv at 0.10 or newer" '
  make_uv "$sandbox/home/.local/bin/uv" 0.11.8
  # No interpreter to install with, so reuse is the only way this can succeed.
  export DRIVERS_TOOLS_PYTHON="$sandbox/no-python-here"
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

# ---------------------------------------------------------------------------
# Host-shape cases.
#
# One container per distro whose interpreters make ensure_uv's job hard, so the
# fallbacks are checked against what those images ship rather than what we assume.
#
# Missing on purpose: RHEL 7 publishes no arm64 image and Amazon Linux 2 has no
# python newer than 3.7 to stand in for the toolchain. Both are structurally the
# RHEL 8.2 case below. debian11 and Ubuntu 20.04 live in
# test-remote-kms-provisioning.sh, which already builds images for them.

if [ -n "${ENSURE_UV_SKIP_CONTAINERS:-}" ]; then
  echo "Skipping ensure_uv host-shape cases (ENSURE_UV_SKIP_CONTAINERS is set)."
elif ! command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
  echo "Skipping ensure_uv host-shape cases (no container engine)."
else
  ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

  # Matches the engine selection in .evergreen/docker/run-server.sh.
  if command -v podman >/dev/null 2>&1; then
    DOCKER="sudo podman --storage-opt ignore_chown_errors=true"
  else
    DOCKER=docker
  fi
  [ -n "${DOCKER_COMMAND:-}" ] && DOCKER=$DOCKER_COMMAND

  # check_container
  #
  # Run $3 inside $2, with a writable copy of the checkout as the working
  # directory. Each case both establishes the shape it tests and guards that the
  # image still has it, so an image that changes under us fails loudly.
  check_container() {
    local name="$1" base_image="$2" script="$3"
    local log
    log=$(mktemp)

    if $DOCKER run --rm -v "$ROOT_DIR:/src:ro" "$base_image" bash -c "
      set -eu
      cp -r /src /root/drivers-tools
      cd /root/drivers-tools
      $script
    " >"$log" 2>&1; then
      echo "  ok: $name ($base_image)"
    else
      echo "  FAIL: $name ($base_image)"
      tail -n 25 "$log" | sed 's/^/    /'
      failures=$((failures + 1))
    fi
    rm -f "$log"
  }

  echo "Testing ensure_uv on real distro images ..."

  # The host this ticket is about. RHEL 8.2's platform python3 is 3.6, which uv
  # has no distribution for, so only the toolchain can succeed here.
  check_container "rhel 8.2: toolchain rescues a 3.6 platform python3" \
    registry.access.redhat.com/ubi8/ubi:8.8 '
    dnf install -y python3 python3.11 >/dev/null 2>&1
    python3 -c "import sys; sys.exit(0 if sys.version_info < (3, 8) else 1)" || {
      echo "expected a platform python3 too old for uv; the image changed"; exit 1
    }
    mkdir -p /opt/mongodbtoolchain/v4/bin
    ln -sf /usr/bin/python3.11 /opt/mongodbtoolchain/v4/bin/python3
    . .evergreen/ensure-uv.sh
    ensure_uv
    uv --version
  '

  # The same image without the toolchain: the failure the ticket reported. Pins
  # the diagnosis, so the case above cannot pass for some other reason.
  check_container "rhel 8.2: fails cleanly when only the 3.6 python3 exists" \
    registry.access.redhat.com/ubi8/ubi:8.8 '
    dnf install -y python3 >/dev/null 2>&1
    . .evergreen/ensure-uv.sh
    if ensure_uv >/dev/null 2>&1; then
      echo "expected ensure_uv to fail with only a 3.6 python3"; exit 1
    fi
  '

  check_container "rhel 9: uses the platform python3" \
    registry.access.redhat.com/ubi9/ubi:9.3 '
    . .evergreen/ensure-uv.sh
    ensure_uv
    uv --version
  '

  check_container "amazon linux 2023: uses the platform python3" \
    amazonlinux:2023 '
    . .evergreen/ensure-uv.sh
    ensure_uv
    uv --version
  '

  # Ubuntu 24.04 enables PEP 668, so only PIP_BREAK_SYSTEM_PACKAGES or the venv
  # gets through.
  check_container "ubuntu 24.04: works despite the PEP 668 guard" \
    ubuntu:24.04 '
    export DEBIAN_FRONTEND=noninteractive
    apt-get -qq update >/dev/null 2>&1
    apt-get -y -qq install python3 python3-venv python3-pip >/dev/null 2>&1
    [ -f /usr/lib/python3*/EXTERNALLY-MANAGED ] || {
      echo "expected a PEP 668 externally-managed marker; the image changed"; exit 1
    }
    . .evergreen/ensure-uv.sh
    ensure_uv
    uv --version
  '
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures ensure_uv test(s) failed." >&2
  exit 1
fi
echo "All ensure_uv tests passed."
