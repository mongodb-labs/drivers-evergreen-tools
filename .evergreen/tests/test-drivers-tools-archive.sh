#!/usr/bin/env bash
#
# Tests make-drivers-tools-archive.sh, which builds the tarball every remote
# VM and pod receives instead of cloning this repo.
#
# Runs against a miniature $DRIVERS_TOOLS built in a temp directory rather than
# the real checkout, so the assertions do not drift as the repo changes.
set -eu

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARCHIVER="$ROOT_DIR/.evergreen/make-drivers-tools-archive.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FAILED=0

pass() {
  echo "  ok: $1"
}

fail() {
  echo "  FAIL: $1" >&2
  FAILED=1
}

assert_file() {
  if [ -f "$2" ]; then pass "$1"; else fail "$1"; fi
}

assert_no_file() {
  if [ -f "$2" ]; then fail "$1"; else pass "$1"; fi
}

assert_contents() {
  local desc="$1" path="$2" want="$3" got
  got=$(cat "$path" 2>/dev/null || true)
  if [ "$got" = "$want" ]; then pass "$desc"; else fail "$desc (want '$want', got '$got')"; fi
}

# The archiver refuses to run on Windows, so assert that rather than skipping.
# Everything below it needs a working archiver, and asserting keeps the refusal
# and its message honest instead of letting them rot untested.
case "$(uname -s)" in
CYGWIN*)
  echo "Testing the archiver refuses to run on Windows ..."
  if bash "$ARCHIVER" "$WORK/out.tgz" >/dev/null 2>"$WORK/err"; then
    fail "archiver should have refused to run on Windows"
  elif grep -q "not supported on Windows" "$WORK/err"; then
    pass "archiver refuses to run on Windows with an actionable error"
  else
    fail "archiver failed on Windows, but not with the expected message"
    cat "$WORK/err" >&2
  fi
  echo "Testing the archiver refuses to run on Windows ... done."
  if [ "$FAILED" -ne 0 ]; then
    echo "FAILED" >&2
    exit 1
  fi
  echo "All archive tests passed."
  exit 0
  ;;
esac

# A git checkout holding a plain tracked file, a tracked file carrying an
# uncommitted edit, and an untracked secrets file in the very location
# azurekms/create-and-setup-vm.sh writes one on the host.
FAKE="$WORK/drivers-tools"
mkdir -p "$FAKE/.evergreen/csfle/azurekms"
git -C "$FAKE" init -q
git -C "$FAKE" config user.email test@example.com
git -C "$FAKE" config user.name "Test"
echo "tracked" >"$FAKE/.evergreen/tracked.sh"
echo "committed" >"$FAKE/.evergreen/edited.sh"
printf '#!/usr/bin/env bash\ntrue\n' >"$FAKE/.evergreen/runnable.sh"
chmod +x "$FAKE/.evergreen/runnable.sh"
git -C "$FAKE" add -A
git -C "$FAKE" commit -qm "initial"
echo "uncommitted" >"$FAKE/.evergreen/edited.sh"
echo "export AZUREKMS_SECRET=hunter2" >"$FAKE/.evergreen/csfle/azurekms/secrets-export.sh"

echo "Testing archive contents ..."
DRIVERS_TOOLS="$FAKE" bash "$ARCHIVER" "$WORK/out.tgz"
OUT="$WORK/extracted"
mkdir -p "$OUT"
tar xzf "$WORK/out.tgz" -C "$OUT"

assert_file "tracked file is included" "$OUT/.evergreen/tracked.sh"

# Every caller extracts with an explicit -C, so a prefix directory would put the
# tree one level too deep on all seven of them.
assert_no_file "archive carries no path prefix" "$OUT/drivers-evergreen-tools/.evergreen/tracked.sh"

# The reason the archive is built from tracked paths rather than a recursive
# copy. Regressing this ships KMS credentials to a test VM.
assert_no_file "untracked secrets-export.sh is excluded" \
  "$OUT/.evergreen/csfle/azurekms/secrets-export.sh"

# Read from the working tree, not HEAD: Evergreen may leave a patch build's diff
# uncommitted, and `git archive HEAD` would ship the pre-patch tree.
assert_contents "uncommitted edit to a tracked file is included" \
  "$OUT/.evergreen/edited.sh" "uncommitted"

# The remote side invokes scripts from the unpacked tree directly, so losing the
# executable bit in transit would break it.
if [ -x "$OUT/.evergreen/runnable.sh" ]; then
  pass "executable bit is preserved"
else
  fail "executable bit is preserved"
fi

echo "Testing archive contents ... done."

echo "Testing failure without git metadata ..."
NOGIT="$WORK/nogit"
mkdir -p "$NOGIT/.evergreen"
if DRIVERS_TOOLS="$NOGIT" bash "$ARCHIVER" "$WORK/nogit.tgz" 2>/dev/null; then
  fail "exits non-zero when \$DRIVERS_TOOLS is not a git checkout"
else
  pass "exits non-zero when \$DRIVERS_TOOLS is not a git checkout"
fi
echo "Testing failure without git metadata ... done."

if [ "$FAILED" -ne 0 ]; then
  echo "FAILED" >&2
  exit 1
fi
echo "All archive tests passed."
