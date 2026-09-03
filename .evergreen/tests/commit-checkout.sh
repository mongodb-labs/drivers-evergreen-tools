#!/usr/bin/env bash
#
# Commit the working tree of $DRIVERS_TOOLS, so a remote VM or pod runs this
# checkout rather than the last commit.
#
# make-drivers-tools-archive.sh ships the tracked paths of the working tree, so a
# patch build's new files reach the remote host only once they are staged.
set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "$SCRIPT_DIR/../handle-paths.sh"

cd "$DRIVERS_TOOLS"
git add .
# Only when something is staged: a build with nothing to commit would otherwise
# fail here under errexit.
git diff --cached --quiet || git commit -m "add files"
