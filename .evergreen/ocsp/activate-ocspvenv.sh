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

if [ -z "$BASHPID" ]; then
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

    venvcreate "$(find_python3)" ocspvenv || return

    if [[ "$OSTYPE" == cygwin && "$HOSTTYPE" == x86_64 ]]; then
      local -r windows_os_name="$(systeminfo.exe /FO LIST | perl -lne 'print $1 if m/^OS Name:\s+(.*)$/' || true)"

      if [[ "$windows_os_name" =~ 2016 ]]; then
        # Avoid `RuntimeError: Could not determine home directory.` on
        # windows-64-2016. See BUILD-16233.
        python -m pip install -U "setuptools<65.0" || {
          local -r ret="$?"
          deactivate || return 1 # Deactivation should never fail!
          return "$ret"
        }
      fi
    fi

    python -m pip install -r mock-ocsp-responder-requirements.txt || {
      local -r ret="$?"
      deactivate || return 1 # Deactivation should never fail!
      return "$ret"
    }
  fi
}

activate_ocspvenv
