#!/usr/bin/env bash
#
# make-drivers-tools-archive.sh
#
# Usage:
#   make-drivers-tools-archive.sh <output.tgz>
#
# Build the gzipped tarball of $DRIVERS_TOOLS that remote VMs and pods unpack
# instead of cloning this repo, so the remote side always runs the same revision
# as the host. Drivers pin $DRIVERS_TOOLS, and a remote `git clone` of the
# default branch silently pairs a pinned provisioning script with unpinned code.
#
# The archive is flat, with no path prefix. Callers pick the destination with
# `tar -C`, which is the only convention that suits every caller.
#
# Two properties come from listing paths with `git ls-files` and reading them
# from the working tree rather than using `git archive HEAD`:
#
# - A patch build's uncommitted edits are included. Evergreen may leave a
#   patch's diff uncommitted, and prepare-env-and-resources.sh copies the
#   working tree into $DRIVERS_TOOLS precisely so patch builds test the patch.
# - Untracked files are skipped. That keeps secrets-export.sh out of the
#   archive, which matters because create-and-setup-vm.sh writes one into
#   .evergreen/csfle/azurekms/ on the host. Surfaces that legitimately need
#   secrets remotely copy them as separate files. It also keeps downloaded
#   server binaries and .local tool state out, holding the transfer near 1.5 MB.
#
# .git is deliberately not shipped. Nothing this repo runs remotely inspects its
# own git metadata.
set -eu

# Unsupported on Windows, by design. Every consumer unpacks this archive on a
# Linux VM or pod, and here git and tar want opposite path forms that cannot both
# be satisfied: native git needs `C:/...`, while Cygwin's GNU tar reads that as an
# rsh `host:path` spec and tries to connect to a machine named `C`. Refuse
# outright rather than emit a broken archive.
#
# Checked before anything else, so refusing costs nothing. Detected the way
# handle-paths.sh does it, which is the form these hosts are known to match.
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

# --no-xattrs because building this on macOS otherwise records com.apple.provenance
# on every entry, and GNU tar on the Linux side then warns once per file. Accepted
# by both bsdtar and GNU tar.
git -C "$DRIVERS_TOOLS" ls-files -z |
  tar czf "$OUTPUT" --no-xattrs -C "$DRIVERS_TOOLS" --null -T -
