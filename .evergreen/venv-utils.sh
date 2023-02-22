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

if [ -z "$BASH" ]; then
  echo "venv-utils.sh must be run in a Bash shell!" 1>&2
  return 1
fi

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
# activated, and all seed packages are successfully installed in the new
# virtual environment.
# Return a non-zero value (false) in a deactivated state otherwise.
#
# The "seed" packages pip, setuptools, and wheel are automatically installed
# into the virtual environment. All packages must be successfully installed for
# venvcreate to be considered a success.
#
# If a file or directory exists at the given path to the virtual environment,
# they may be deleted as part of virtual environment creation.
venvcreate() {
  local -r bin="${1:?'venvcreate requires a Python binary to use for the virtual environment'}"
  local -r path="${2:?'venvcreate requires a path to the virtual environment to create'}"

  if [[ "$OSTYPE" == cygwin ]]; then
    local -r real_path="$(cygpath -aw "$path")" || return
  else
    local -r real_path="$path" || return
  fi

  # Prefer venv, but fallback to virtualenv if venv fails.
  for mod in "venv" "virtualenv"; do
    # Ensure a clean directory before attempting to create a virtual
    # environment.
    rm -rf "$path"

    case "$mod" in
    venv)
      "$bin" -m "$mod" --system-site-packages "$real_path" || continue
      ;;
    virtualenv)
      # -p: some old versions of virtualenv (e.g. installed on Debian 10) are
      # buggy. Without -p, the created virtual environment may use the wrong
      # Python binary (e.g. using a Python 2 binary even if it was created by a
      # Python 3 binary).
      "$bin" -m "$mod" -p "$bin" --system-site-packages "$real_path" || continue
      ;;
    *)
      echo "Unexpected virtual environment module $mod!"
      return 1
      ;;
    esac

    # Workaround https://github.com/python/cpython/issues/76632:
    # activate: line 3: $'\r': command not found
    if [[ -f "$path/Scripts/activate" ]]; then
      dos2unix -q "$path/Scripts/activate" || true
    fi

    venvactivate "$path" || continue

    if ! python -m pip install -U pip; then
      deactivate || return 1 # Deactivation should never fail!
      continue
    fi

    # Ensure setuptools and wheel are installed in the virtual environment.
    # virtualenv only guarantees "one or more of" the seed packages are
    # installed. venv only guarantees pip is installed via ensurepip.
    #
    # These packages must be upgraded *after* pip, *separately*, as some old
    # versions of pip do not handle their simultaneous installation properly.
    # See: https://github.com/pypa/pip/issues/4253
    if ! python -m pip install -U setuptools wheel; then
      deactivate || return 1 # Deactivation should never fail!
      continue
    fi

    # Success only if both activation and package upgrades are successful.
    return 0
  done

  echo "Could not use either venv or virtualenv with $bin to create a virtual environment at $path!" 1>&2
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
