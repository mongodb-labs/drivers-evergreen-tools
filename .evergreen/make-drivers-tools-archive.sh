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
# with server binaries and .local, holding the transfer near 1.5 MB.
set -eu

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

# --no-xattrs: building on macOS otherwise records com.apple.provenance on every
# entry, which GNU tar then warns about once per file. Both tars accept the flag.
git -C "$DRIVERS_TOOLS" ls-files -z |
  tar czf "$OUTPUT" --no-xattrs -C "$DRIVERS_TOOLS" --null -T -
