#!/usr/bin/env bash
#
# activate-kmstlsvenv.sh
#
# Usage:
#   . ./activate-kmstlsvenv.sh
#
# This file creates and/or activates the kmstlsvenv virtual environment in the
# current working directory. This file must be invoked from within the
# .evergreen/csfle directory in the Drivers Evergreen Tools repository.
#
# If a kmstlsvenv virtual environment already exists, it will be activated and
# no further action will be taken. If a kmstlsvenv virtual environment must be
# created, required packages will also be installed.

# If an error occurs during creation, activation, or installation of packages,
# the kmstlsvenv virtual environment will be deactivated and activate_kmstlsvenv
# will return a non-zero value.

if [ -z "$BASH" ]; then
  echo "activate-kmstlsvenv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# Automatically invoked by activate-kmstlsvenv.sh.
activate_kmstlsvenv() {
  # shellcheck source=.evergreen/venv-utils.sh
  . ../venv-utils.sh || return

  if [[ -d kmstlsvenv ]]; then
    venvactivate kmstlsvenv || return
  else
    # shellcheck source=.evergreen/find-python3.sh
    . ../find-python3.sh || return

    echo "Creating virtual environment 'kmstlsvenv'..."
    echo "Finding Python3 binary..."
    PYTHON="$(find_python3 2>/dev/null)"
    echo "Finding Python3 binary... done."
    venvcreate $PYTHON kmstlsvenv || return

    local packages=(
      "boto3~=1.19.0"
      "git+https://github.com/kevinAlbs/PyKMIP.git@DRIVERS-2659" # Add work around for DRIVERS-2659
      "sqlalchemy<2.0.0" # sqlalchemy.exc.InvalidRequestError: Implicitly combining column managed_objects.uid with column crypto_objects.uid under attribute 'unique_identifier'.
    )

    if [[ "$OSTYPE" == darwin16 && "$HOSTTYPE" == x86_64 ]]; then
      # Avoid `error: thread-local storage is not supported for the current
      # target` on macos-1012.
      packages+=("greenlet<2.0")
    fi

    if ! python -m pip install -q -U "${packages[@]}"; then
      # Avoid `error: can't find Rust compiler`.
      # Assume install failure at this point is due to new versions of
      # cryptography require a Rust toolchain when a cryptography wheel is not
      # present due to the package versions available.  This is required by at
      # least the following distros (by OS and host):
      #  - RHEL 6.2
      #  - All RHEL on powerpc64le or s390x.
      #  - OpenSUSE 12 on s390x.
      #  - Ubuntu 18.04 on powerpc64le or s390x
      packages+=("cryptography<3.4")

      python -m pip install -q -U "${packages[@]}" || {
        local -r ret="$?"
        deactivate || return 1 # Deactivation should never fail!
        return "$ret"
      }
    fi
    echo "Creating virtual environment 'kmstlsvenv'... done."
  fi
}

activate_kmstlsvenv
