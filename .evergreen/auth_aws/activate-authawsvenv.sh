#!/usr/bin/env bash
#
# activate-authawsvenv.sh
#
# Usage:
#   . ./activate-authawsvenv.sh
#
# This file creates and/or activates the authawsvenv virtual environment in the
# current working directory. This file must be invoked from within the
# .evergreen/auth_aws directory in the Drivers Evergreen Tools repository.
#
# If a authawsvenv virtual environment already exists, it will be activated and
# no further action will be taken. If a authawsvenv virtual environment must be
# created, required packages will also be installed.

# If an error occurs during creation, activation, or installation of packages,
# the authawsvenv virtual environment will be deactivated and activate_authawsvenv
# will return a non-zero value.

if [ -z "$BASH" ]; then
  echo "activate-authawsvenv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# Automatically invoked by activate-authawsvenv.sh.
activate_authawsvenv() {
  # shellcheck source=.evergreen/venv-utils.sh
  . ../venv-utils.sh || return

  if [[ -d authawsvenv ]]; then
    venvactivate authawsvenv || return
  else
    # shellcheck source=.evergreen/find-python3.sh
    . ../find-python3.sh || return

    echo "Creating virtual environment 'authawsvenv'..."

    venvcreate "$(find_python3 2>/dev/null)" authawsvenv || return

    local packages=(
      "boto3~=1.26.0"
      "pyop~=3.4.0"
      "pymongo[aws]~=4.0"
    )

    python -m pip install -q -U "${packages[@]}" || {
      local -r ret="$?"
      deactivate || return 1 # Deactivation should never fail!
      return "$ret"
    }
  fi
}

activate_authawsvenv
