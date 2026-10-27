#!/usr/bin/env bash
#
# activate-kmstlsvenv.sh
#
# Usage:
#   . ./activate-kmstlsvenv.sh
#
# Creates and/or activates the root workspace .venv with the csfle group and
# ensures the sdist build toolchain for cryptography, which uv needs on
# s390x. Delegates to the shared helper, ../activate-uv-venv.sh.

if [ -z "$BASH" ]; then
  echo "activate-kmstlsvenv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# shellcheck source=.evergreen/activate-uv-venv.sh
. "$(dirname "${BASH_SOURCE[0]}")/../activate-uv-venv.sh" || return 1

activate_uv_venv csfle --cryptography-build
