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
# The unsearchable-directory case below would otherwise defeat the cleanup.
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

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

# A git checkout holding a plain tracked file, one carrying an uncommitted edit,
# one deleted without staging it, a whole removed directory, a dangling tracked
# symlink, and an untracked secrets file where azurekms writes one on the host.
FAKE="$WORK/drivers-tools"
mkdir -p "$FAKE/.evergreen/csfle/azurekms"
git -C "$FAKE" init -q
git -C "$FAKE" config user.email test@example.com
git -C "$FAKE" config user.name "Test"
echo "tracked" >"$FAKE/.evergreen/tracked.sh"
echo "committed" >"$FAKE/.evergreen/edited.sh"
echo "doomed" >"$FAKE/.evergreen/deleted.sh"
mkdir -p "$FAKE/.evergreen/removed/nested"
echo "gone" >"$FAKE/.evergreen/removed/nested/buried.sh"
printf '#!/usr/bin/env bash\ntrue\n' >"$FAKE/.evergreen/runnable.sh"
chmod +x "$FAKE/.evergreen/runnable.sh"
ln -s missing-target "$FAKE/.evergreen/dangling.pem"
git -C "$FAKE" add -A
git -C "$FAKE" commit -qm "initial"
echo "uncommitted" >"$FAKE/.evergreen/edited.sh"
rm "$FAKE/.evergreen/deleted.sh"
rm -rf "$FAKE/.evergreen/removed"
echo "export AZUREKMS_SECRET=hunter2" >"$FAKE/.evergreen/csfle/azurekms/secrets-export.sh"

echo "Testing archive contents ..."
# Guarded rather than bare: a non-zero exit here would otherwise take the suite
# down through `set -e` without naming what broke. Its stderr is echoed instead.
if ! DRIVERS_TOOLS="$FAKE" bash "$ARCHIVER" "$WORK/out.tgz" 2>"$WORK/build.err"; then
  fail "archiver exits zero over a checkout with deletions but nothing unreadable"
  sed 's/^/    /' "$WORK/build.err" >&2
  echo "FAILED" >&2
  exit 1
fi
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

# An unstaged removal leaves the path in the index, and tar aborts on it.
assert_no_file "tracked file deleted in the working tree is excluded" \
  "$OUT/.evergreen/deleted.sh"

# A removed directory takes its parent with it, so the unsearchable-ancestor guard
# must walk past the missing levels. Firing here would fail every patch that
# deletes a directory.
assert_no_file "tracked file under a removed directory is excluded" \
  "$OUT/.evergreen/removed/nested/buried.sh"

# Deleted paths are dropped by testing existence, which a dangling symlink fails,
# so surviving takes an explicit -L. x509gen and orchestration/lib track symlinks.
if [ -L "$OUT/.evergreen/dangling.pem" ]; then
  pass "tracked symlink is included even with a missing target"
else
  fail "tracked symlink is included even with a missing target"
fi

echo "Testing archive contents ... done."

echo "Testing failure when git fails mid-pipeline ..."
# The file list is piped into tar, so a git that dies partway leaves tar writing a
# short archive. Unless that surfaces, callers ship a truncated tree.
REAL_GIT=$(command -v git)
STUB_BIN="$WORK/stub-bin"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/git" <<EOF
#!/usr/bin/env bash
# Fails only ls-files, so the archiver's is-this-a-checkout guard still passes.
for arg in "\$@"; do
  if [ "\$arg" = "ls-files" ]; then
    echo "stub git: simulated ls-files failure" >&2
    exit 1
  fi
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$STUB_BIN/git"

if PATH="$STUB_BIN:$PATH" DRIVERS_TOOLS="$FAKE" bash "$ARCHIVER" "$WORK/broken.tgz" \
  2>/dev/null; then
  fail "exits non-zero when git ls-files fails"
else
  pass "exits non-zero when git ls-files fails"
fi
echo "Testing failure when git fails mid-pipeline ... done."

echo "Testing refusal when a path's absence cannot be established ..."
# An unsearchable directory makes its contents unstattable, and git reports those
# paths as --deleted just as it does real deletions. Skipping them silently would
# drop tracked files that are actually present.
if [ "$(id -u)" -eq 0 ]; then
  # Root ignores directory permissions, so the condition cannot be staged here.
  echo "  skip: running as root, cannot make a directory unsearchable"
else
  LOCKED="$WORK/locked"
  mkdir -p "$LOCKED/.evergreen/private"
  git -C "$LOCKED" init -q
  git -C "$LOCKED" config user.email test@example.com
  git -C "$LOCKED" config user.name "Test"
  echo "visible" >"$LOCKED/.evergreen/visible.sh"
  echo "hidden" >"$LOCKED/.evergreen/private/hidden.sh"
  git -C "$LOCKED" add -A
  git -C "$LOCKED" commit -qm "initial"
  chmod 000 "$LOCKED/.evergreen/private"

  if DRIVERS_TOOLS="$LOCKED" bash "$ARCHIVER" "$WORK/locked.tgz" \
    2>"$WORK/locked.err"; then
    fail "exits non-zero when a tracked path can neither be read nor ruled out"
    if [ -f "$WORK/locked.tgz" ] &&
      ! tar tzf "$WORK/locked.tgz" 2>/dev/null | grep -q "private/hidden.sh"; then
      echo "    (it built an archive silently missing private/hidden.sh)" >&2
    fi
  elif grep -q "cannot determine whether" "$WORK/locked.err"; then
    pass "refuses to guess when a directory is not searchable"
  else
    fail "exited non-zero, but not with the expected message"
    cat "$WORK/locked.err" >&2
  fi

  # Restore before the archive-wide cleanup so nothing depends on trap ordering.
  chmod 755 "$LOCKED/.evergreen/private"
fi
echo "Testing refusal when a path's absence cannot be established ... done."

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
