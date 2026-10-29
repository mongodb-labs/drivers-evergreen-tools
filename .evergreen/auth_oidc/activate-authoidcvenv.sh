#!/usr/bin/env bash
#
# activate-authoidcvenv.sh
#
# Usage:
#   . ./activate-authoidcvenv.sh
#
# Creates and/or activates the root workspace .venv with the auth_oidc
# group. Delegates to the shared helper, ../activate-uv-venv.sh.

if [ -z "$BASH" ]; then
  echo "activate-authoidcvenv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# shellcheck source=.evergreen/activate-uv-venv.sh
. "$(dirname "${BASH_SOURCE[0]}")/../activate-uv-venv.sh" || return 1

activate_uv_venv auth_oidc
