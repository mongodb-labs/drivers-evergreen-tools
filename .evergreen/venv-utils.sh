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
#
# If a file or directory exists at the given path to the virtual environment,
# they may be deleted as part of virtual environment creation.
venvcreate() {
  local -r bin="${1:?'venvcreate requires a Python binary to use for the virtual environment'}"
  local -r path="${2:?'venvcreate requires a path to the virtual environment to create'}"

  # Prefer venv, but fallback to virtualenv if venv fails.
  for mod in "venv" "virtualenv"; do
    # Ensure a clean directory before attempting to create a virtual environment.
    rm -rf "$path"

    if "$bin" -m "$mod" "$path"; then
      # Workaround https://bugs.python.org/issue32451:
      # mongovenv/Scripts/activate: line 3: $'\r': command not found
      if [[ -f "$path/Scripts/activate" ]]; then
        dos2unix "$path/Scripts/activate" || true
      fi

      if venvactivate "$path"; then
        # Use --no-cache-dir to ensure ensure the *actual* latest pip is
        # correctly installed.
        if python -m pip install --no-cache-dir --upgrade pip; then
          # Only consider success if activation + pip upgrade was successful.
          return
        fi

        deactivate
      fi
    fi
  done

  echo "Could not use either venv or virtualenv to create the virtual environment at $path!" 1>&2
  return 1
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
