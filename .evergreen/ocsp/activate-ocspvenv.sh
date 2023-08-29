#!/usr/bin/env bash
#
# activate-ocspvenv.sh
#
# Usage:
#   . ./activate-ocspvenv.sh
#
# This file creates and/or activates the ocspvenv virtual environment in the
# current working directory. This file must be invoked from within the
# .evergreen/ocsp directory in the Drivers Evergreen Tools repository.
#
# If a ocspvenv virtual environment already exists, it will be activated and
# no further action will be taken. If a ocspvenv virtual environment must be
# created, required packages will also be installed.

# If an error occurs during creation, activation, or installation of packages,
# the ocspvenv virtual environment will be deactivated and activate_ocspvenv
# will return a non-zero value.

if [ -z "$BASH" ]; then
  echo "activate-kmstlsvenv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# Automatically invoked by activate-ocspvenv.sh.
activate_ocspvenv() {
  # shellcheck source=.evergreen/venv-utils.sh
  . ../venv-utils.sh || return

  if [[ -d ocspvenv ]]; then
    venvactivate ocspvenv || return
  else
    # shellcheck source=.evergreen/find-python3.sh
    . ../find-python3.sh || return

    echo "Creating virtual environment 'ocspvenv'..."
    echo "Finding Python3 binary..."
    PYTHON="$(find_python3 2>/dev/null)"
    echo "Finding Python3 binary... done."
    venvcreate $PYTHON ocspvenv || return

    python -m pip install -q -r mock-ocsp-responder-requirements.txt || {
      local -r ret="$?"
      deactivate || return 1 # Deactivation should never fail!
      return "$ret"
    }
    echo "Creating virtual environment 'ocspvenv'... done."
  fi
}

activate_ocspvenv
