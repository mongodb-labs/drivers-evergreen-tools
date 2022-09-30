#!/usr/bin/env bash
#
# venv-utils.sh
#
# Usage:
#   . /path/to/venv-utils.sh
#
# This file defines the following functions:
#   - venvcreate
#   - venvactivate
# These functions may be invoked from any working directory.

# venvcreate
#
# Usage:
#   venvcreate python venv
#   venvcreate /path/to/python /path/to/venv/dir
#
# Parameters:
#   "$1": The Python binary to use for the virtual environment.
#   "$2": The path to the virtual environment (directory) to create.
#
# Return 0 (true) if the virtual environment has been successfully created,
# activated, and the pip package upgraded.
# Return a non-zero value (false) otherwise.
venvcreate() {
  local -r bin="${1:?'venvcreate requires a Python binary to use for the virtual environment'}"
  local -r path="${2:?'venvcreate requires a path to the virtual environment to create'}"

  if "$bin" -m venv -h &>/dev/null; then
    "$bin" -m venv "$path" || return 1
  elif "$bin" -m virtualenv --version &>/dev/null; then
    # Ensure the correct binary is used for the virtual environment with the
    # '-p` argument. System-installed virtualenv on Debian 10 is buggy and
    # may default to creating a python2 environment otherwise.
    "$bin" -m virtualenv -p "$bin" "$path" || return 1
  else
    echo "Could not use either venv or virtualenv to create the virtual environment at $path!" 1>&2
    return 1
  fi

  # Workaround https://bugs.python.org/issue32451:
  # mongovenv/Scripts/activate: line 3: $'\r': command not found
  if [[ -f "$path/Scripts/activate" ]]; then
    dos2unix "$path/Scripts/activate" || true
  fi

  venvactivate "$path" || return 1

  python -m pip install --upgrade pip
}

# venvactivate
#
# Usage:
#   venvactivate venv
#   venvactivate /path/to/venv/dir
#
# Parameters:
#   "$1": The path to an existing virtual environment (directory).
#
# Activate the virtual environment "$1". Designed to work regardless of the
# target environment.
venvactivate() {
  local -r path="${1:?'venvactivate requires a path to an existing virtual environment'}"

  if [[ -f "$path/bin/activate" ]]; then
    # shellcheck source=/dev/null
    . "$path/bin/activate"
  elif [[ -f "$path/Scripts/activate" ]]; then
    # shellcheck source=/dev/null
    . "$path/Scripts/activate"
  else
    echo "Could not find the script to activate the virtual environment at $path!" 1>&2
    return 1
  fi
}
