#!/usr/bin/env bash
#
# Asserts the gcpkms/azurekms start-mongodb.sh scripts start the server from the
# archive the host ships them, rather than cloning drivers-tools (DRIVERS-3564).
#
# Provisioning is not covered here. The kms and kms-legacy build variants run
# these scripts against real VMs, which is the only place the host shape is real.
set -eu

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Runs locally rather than in a container: the branch under test is pure shell,
# and the archive here holds a stub run-orchestration.sh so no server is started.
test_start_mongodb_uses_archive() {
  local name="$1" script="$2"
  echo "Testing $name start-mongodb.sh uses the archive ..."
  local work stub
  work=$(mktemp -d)
  stub="$work/stub-drivers-tools"

  mkdir -p "$stub/.evergreen/orchestration"
  git -C "$stub" init -q
  git -C "$stub" config user.email test@example.com
  git -C "$stub" config user.name "Test"
  printf '#!/usr/bin/env bash\necho ran-from-archive > "$(dirname "${BASH_SOURCE[0]}")/../marker"\n' \
    >"$stub/.evergreen/run-orchestration.sh"
  chmod +x "$stub/.evergreen/run-orchestration.sh"
  # start-mongodb.sh writes orchestration.config here, and git does not track
  # empty directories, so the directory needs a file to survive the archive.
  touch "$stub/.evergreen/orchestration/.keep"
  git -C "$stub" add -A
  git -C "$stub" commit -qm "stub"

  mkdir -p "$work/vm"
  DRIVERS_TOOLS="$stub" bash "$ROOT_DIR/.evergreen/make-drivers-tools-archive.sh" \
    "$work/vm/drivers-evergreen-tools.tgz"

  # The remote scripts run from the home directory with the tarball beside them.
  ( cd "$work/vm" && bash "$ROOT_DIR/$script" ) >"$work/out.log" 2>&1 || {
    echo "  FAIL: $name start-mongodb.sh exited non-zero" >&2
    cat "$work/out.log" >&2; rm -rf "$work"; return 1
  }
  if [ ! -f "$work/vm/drivers-evergreen-tools/marker" ]; then
    echo "  FAIL: $name did not run run-orchestration.sh from the archive" >&2
    cat "$work/out.log" >&2; rm -rf "$work"; return 1
  fi
  if grep -q "cloning the default branch" "$work/out.log"; then
    echo "  FAIL: $name fell back to cloning despite the archive being present" >&2
    rm -rf "$work"; return 1
  fi
  echo "  ok: unpacked the archive and did not fall back to cloning"
  rm -rf "$work"
  echo "Testing $name start-mongodb.sh uses the archive ... done."
}

test_start_mongodb_uses_archive gcpkms .evergreen/csfle/gcpkms/remote-scripts/start-mongodb.sh
test_start_mongodb_uses_archive azurekms .evergreen/csfle/azurekms/remote-scripts/start-mongodb.sh
