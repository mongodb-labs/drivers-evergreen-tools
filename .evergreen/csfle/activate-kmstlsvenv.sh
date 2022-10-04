#!/usr/bin/env bash
#
# activate-kmstlsvenv.sh
#
# Usage:
#   . ./activate-kmstlsvenv.sh
#
# This file creates and activates the kmstlsvenv virtual environment in the
# current working directory. This file must be invoked from within the
# .evergreen/csfle directory in the Drivers Evergreen Tools repository.

# Automatically invoked by activate-kmstlsvenv.sh.
activate_kmstlsvenv() {
  # shellcheck source=.evergreen/venv-utils.sh
  . ../venv-utils.sh || return 1

  if [[ -d kmstlsvenv ]]; then
    venvactivate kmstlsvenv
  else
    # shellcheck source=.evergreen/find-python3.sh
    . ../find-python3.sh || return 1

    venvcreate "$(find_python3)" kmstlsvenv || return 1

    CRYPTOGRAPHY_DONT_BUILD_RUST=1 python -m pip install --upgrade boto3~=1.19 cryptography~=3.4.8 pykmip~=0.10.0
  fi
}

activate_kmstlsvenv
