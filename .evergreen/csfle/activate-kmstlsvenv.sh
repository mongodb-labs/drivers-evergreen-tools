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

# Automatically invoked by activate-kmstlsvenv.sh.
activate_kmstlsvenv() {
  # shellcheck source=.evergreen/venv-utils.sh
  . ../venv-utils.sh || return

  if [[ -d kmstlsvenv ]]; then
    venvactivate kmstlsvenv || return
  else
    # shellcheck source=.evergreen/find-python3.sh
    . ../find-python3.sh || return

    venvcreate "$(find_python3)" kmstlsvenv || return

    local packages=(
      "boto3~=1.19.0"
      "pykmip~=0.10.0"
    )

    if [[ "$OSTYPE" == darwin16 && "$HOSTTYPE" == x86_64 ]]; then
      # Avoid `error: thread-local storage is not supported for the current
      # target` on macos-1012.
      packages+=("greenlet<2.0")
    fi

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

    # Avoid `error: can't find Rust compiler`.
    if [[ "$OSTYPE" =~ linux && ! -f /etc/os-release ]]; then
      # rhel62-* is the only suppoerted Linux-like distro that does not provide
      # /etc/os-release. Remove this condition once support for rhel62 is
      # dropped.
      packages+=("cryptography<3.4")
    elif [[ "$OSTYPE" =~ linux ]]; then
      local -r os_id="$(perl -lne 'print $1 if m/^ID="?([^"]+)"?/' /etc/os-release || true)"
      local -r os_ver="$(perl -lne 'print $1 if m/^VERSION_ID="?([^"]+)"?/' /etc/os-release || true)"

      case "$os_id" in
      rhel)
        if [[ "$HOSTTYPE" =~ (powerpc64le|s390x) ]]; then
          # rhelXY-power8-* and rhelXY-zseries-*
          packages+=("cryptography<3.4")
        fi
        ;;
      sles)
        if [[ "$os_ver" == 12.3 && "$HOSTTYPE" == s390x ]]; then
          # suse12-zseries-*
          packages+=("cryptography<3.4")
        fi
        ;;
      ubuntu)
        if [[ "$os_ver" == 18.04 && "$HOSTTYPE" =~ (s390x|powerpc64le) ]]; then
          # ubuntu1804-power8-* and ubuntu1804-zseries-*
          packages+=("cryptography<3.4")
        fi
        ;;
      esac
    fi

    python -m pip install -U "${packages[@]}" || {
      local -r ret="$?"
      deactivate || return 1 # Deactivation should never fail!
      return "$ret"
    }
  fi
}

activate_kmstlsvenv
