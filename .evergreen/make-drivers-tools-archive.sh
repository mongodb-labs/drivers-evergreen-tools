#!/usr/bin/env bash
#
# make-drivers-tools-archive.sh
#
# Usage:
#   make-drivers-tools-archive.sh <output.tgz>
#
# Build the gzipped tarball of $DRIVERS_TOOLS that remote VMs and pods unpack
# instead of cloning this repo, so the remote side runs the host's revision.
# Drivers pin $DRIVERS_TOOLS, and a remote clone of the default branch would pair
# a pinned provisioning script with unpinned code.
#
# Flat, no path prefix: callers pick the destination with `tar -C`. .git is not
# shipped; nothing this repo runs remotely inspects it.
#
# Tracked paths read from the working tree, rather than `git archive HEAD`, so a
# patch build's uncommitted edits are included and untracked files are not. That
# keeps out secrets-export.sh, which azurekms writes into .evergreen/csfle/, along
# with server binaries and .local, holding the transfer under 500 KB.
#
# pipefail matters here: the file list reaches tar through a pipe, so a git that
# dies partway would otherwise leave tar writing a short archive and exiting zero.
set -eu -o pipefail

# Unsupported on Windows: git and tar want opposite path forms there, since native
# git needs `C:/...` while Cygwin's GNU tar reads that as an rsh `host:path` and
# tries to connect to a host named `C`. Every consumer unpacks on Linux anyway.
# Checked first, so refusing costs nothing. Detection matches handle-paths.sh.
case "$(uname -s)" in
CYGWIN*)
  echo "ERROR: make-drivers-tools-archive.sh is not supported on Windows." >&2
  echo "Every remote target that consumes this archive runs Linux, so build it there." >&2
  exit 1
  ;;
esac

if [ $# -ne 1 ]; then
  echo "usage: make-drivers-tools-archive.sh <output.tgz>" >&2
  exit 1
fi
OUTPUT="$1"

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "$SCRIPT_DIR/handle-paths.sh"

if ! git -C "$DRIVERS_TOOLS" rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: $DRIVERS_TOOLS is not a git checkout, cannot build an archive." >&2
  exit 1
fi

# Prints the ancestor that makes $1's absence unverifiable, if any. An unsearchable
# directory leaves everything beneath it unstattable, and git reports those paths as
# --deleted just as it does real deletions. The deepest ancestor that exists settles
# it: searchable means the path is truly gone, unsearchable means we cannot tell.
unsearchable_ancestor() {
  local dir
  dir=$(dirname "$1")
  while [ "$dir" != "/" ] && [ "$dir" != "." ] && [ ! -e "$dir" ]; do
    dir=$(dirname "$dir")
  done
  if [ -x "$dir" ]; then
    return 1
  fi
  printf '%s' "$dir"
}

# --no-xattrs: building on macOS otherwise records com.apple.provenance on every
# entry, which GNU tar then warns about once per file. Both tars accept the flag.
git -C "$DRIVERS_TOOLS" ls-files -z |
  while IFS= read -r -d '' path; do
    # Skip what is not in the working tree: a patch build can delete a tracked file
    # without staging it, and tar aborts the whole archive on the first entry it
    # cannot stat. Same set as subtracting `git ls-files --deleted` ("in the index,
    # missing from the working tree"), as a stat per path -- subtracting two
    # NUL-delimited lists costs a subprocess each and leans on a `-z` whose meaning
    # varies across greps. -L is required: -e follows the link, so a tracked
    # symlink with a missing target would be dropped though tar handles it fine.
    if [ -e "$DRIVERS_TOOLS/$path" ] || [ -L "$DRIVERS_TOOLS/$path" ]; then
      printf '%s\0' "$path"
    elif blocker=$(unsearchable_ancestor "$DRIVERS_TOOLS/$path"); then
      rel=${blocker#"$DRIVERS_TOOLS"/}
      echo "ERROR: cannot determine whether $path exists." >&2
      echo "Its ancestor $rel is not searchable, which leaves a deleted file" >&2
      echo "and an unreadable one looking identical from here." >&2
      echo "Refusing to build an archive that may silently omit tracked files." >&2
      echo "Fix that directory's permissions (chmod +rx) and rebuild." >&2
      exit 1
    fi
  done |
  tar czf "$OUTPUT" --no-xattrs -C "$DRIVERS_TOOLS" --null -T -
