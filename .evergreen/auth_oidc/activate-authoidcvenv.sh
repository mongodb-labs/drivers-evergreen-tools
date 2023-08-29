#!/usr/bin/env bash
#
# activate-authoidcvenv.sh
#
# Usage:
#   . ./activate-authoidcvenv.sh
#
# This file creates and/or activates the authoidcvenv virtual environment in the
# current working directory. This file must be invoked from within the
# .evergreen/auth_aws directory in the Drivers Evergreen Tools repository.
#
# If a authoidcvenv virtual environment already exists, it will be activated and
# no further action will be taken. If a authoidcvenv virtual environment must be
# created, required packages will also be installed.

# If an error occurs during creation, activation, or installation of packages,
# the authoidcvenv virtual environment will be deactivated and activate_authoidcvenv
# will return a non-zero value.

if [ -z "$BASH" ]; then
  echo "activate-authoidcvenv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# Automatically invoked by activate-authoidcvenv.sh.
activate_authoidcvenv() {
  # shellcheck source=.evergreen/venv-utils.sh
  . ../venv-utils.sh || return

  if [[ -d authoidcvenv ]]; then
    venvactivate authoidcvenv || return
  else
    # shellcheck source=.evergreen/find-python3.sh
    . ../find-python3.sh || return

    echo "Creating virtual environment 'authoidcvenv'..."
    echo "Finding Python3 binary..."
    PYTHON="$(find_python3 2>/dev/null)"
    echo "Finding Python3 binary... done."
    venvcreate $PYTHON authoidcvenv || return

    local packages=(
      "boto3~=1.19.0"
      "pyop~=3.4.0"
      "azure-identity"
      "azure-keyvault-secrets"
    )
    python -m pip install -q -U "${packages[@]}" || {
      local -r ret="$?"
      deactivate || return 1 # Deactivation should never fail!
      return "$ret"
    }
    echo "Creating virtual environment 'authoidcvenv'... done."
  fi
}

activate_authoidcvenv
