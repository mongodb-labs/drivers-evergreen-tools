#!/usr/bin/env bash
#
# activate-ocspvenv.sh
#
# Usage:
#   . ./activate-ocspvenv.sh
#
# Creates and/or activates the root workspace .venv with the ocsp group and
# ensures the sdist build toolchain for cryptography, which uv needs on
# s390x. Delegates to the shared helper, ../activate-uv-venv.sh.

if [ -z "$BASH" ]; then
  echo "activate-ocspvenv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# shellcheck source=.evergreen/activate-uv-venv.sh
. "$(dirname "${BASH_SOURCE[0]}")/../activate-uv-venv.sh" || return 1

activate_uv_venv ocsp --cryptography-build
