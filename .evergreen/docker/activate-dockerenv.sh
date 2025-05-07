#!/usr/bin/env bash
#
# activate-dockervenv.sh
#
# Usage:
#   . ./activate-dockervenv.sh
#
# This file creates and/or activates the dockervenv virtual environment in the
# current working directory. This file must be invoked from within the
# .evergreen/ocsp directory in the Drivers Evergreen Tools repository.
#
# If a dockervenv virtual environment already exists, it will be activated and
# no further action will be taken. If a dockervenv virtual environment must be
# created, required packages will also be installed.

# If an error occurs during creation, activation, or installation of packages,
# the dockervenv virtual environment will be deactivated and activate_dockervenv
# will return a non-zero value.

if [ -z "$BASH" ]; then
  echo "activate-dockervenv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# Automatically invoked by activate-dockervenv.sh.
activate_dockervenv() {
  # shellcheck source=.evergreen/venv-utils.sh
  . ../venv-utils.sh || return

  if [[ -d dockervenv ]]; then
    venvactivate dockervenv || return
  else
    # shellcheck source=.evergreen/find-python3.sh
    . ../find-python3.sh || return
    PYTHON=$(ensure_python3) || return

    echo "Creating virtual environment 'dockervenv'..."
    venvcreate "${PYTHON:?}" dockervenv || return

    python -m pip install -q -r requirements.txt || {
      local -r ret="$?"
      deactivate || return 1 # Deactivation should never fail!
      return "$ret"
    }
    echo "Creating virtual environment 'dockervenv'... done."
  fi
}

activate_dockervenv
